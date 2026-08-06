-- Billing Phase 4 follow-up: the stored Admin-selected pay-type taxability is authoritative.
-- This migration intentionally does not seed or rewrite any pay_type_rules rows.

alter table public.pay_type_rules
  drop constraint if exists ck_pay_type_rules_only_warranty_tax_exempt;
alter table public.pay_type_rules
  drop constraint if exists ck_pay_type_rules_tax_fields_synchronized;
alter table public.pay_type_rules
  add constraint ck_pay_type_rules_tax_fields_synchronized
  check (tax_applicable = is_taxable);

CREATE OR REPLACE FUNCTION public.resolve_billing_tax_state(p_pay_type text, p_taxable_base numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_rule public.pay_type_rules%ROWTYPE;
    v_is_taxable boolean;
    v_tax_rate numeric;
    v_tax_amount numeric;
    v_rate_source text;
    v_explanation text;
BEGIN
    IF p_pay_type IS NULL OR btrim(p_pay_type) = '' THEN
        RAISE EXCEPTION 'Pay type is required'
            USING ERRCODE = '22023';
    END IF;

    IF p_taxable_base IS NULL
       OR p_taxable_base < 0
       OR p_taxable_base::text IN ('NaN', 'Infinity', '-Infinity') THEN
        RAISE EXCEPTION 'Taxable base must be a finite nonnegative amount'
            USING ERRCODE = '22023';
    END IF;

    SELECT rule.*
    INTO v_rule
    FROM public.pay_type_rules rule
    WHERE rule.pay_type = btrim(p_pay_type)
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pay type is not configured'
            USING ERRCODE = '22023';
    END IF;

    IF NOT (v_rule.is_active AND coalesce(v_rule.active, false)) THEN
        RAISE EXCEPTION 'Pay type is not active'
            USING ERRCODE = '22023';
    END IF;

    IF v_rule.is_taxable IS NULL
       OR v_rule.tax_applicable IS DISTINCT FROM v_rule.is_taxable THEN
        RAISE EXCEPTION 'Pay-type tax configuration is invalid'
            USING ERRCODE = '22023';
    END IF;

    v_is_taxable := v_rule.is_taxable;

    IF NOT v_is_taxable THEN
        v_tax_rate := 0;
        v_tax_amount := 0;
        v_rate_source := 'pay_type_exemption';
        v_explanation :=
            v_rule.pay_type || ' is configured as exempt from loaner and rental tax.';
    ELSE
        SELECT (setting.setting_value #>> '{}')::numeric
        INTO v_tax_rate
        FROM public.admin_settings setting
        WHERE setting.setting_key = 'billing.loaner_rental_tax_rate'
          AND jsonb_typeof(setting.setting_value) = 'number';

        IF v_tax_rate IS NULL
           OR v_tax_rate < 0
           OR v_tax_rate > 1
           OR v_tax_rate::text IN ('NaN', 'Infinity', '-Infinity') THEN
            RAISE EXCEPTION
                'Loaner and rental tax configuration is missing or invalid'
                USING ERRCODE = '22023';
        END IF;

        v_tax_amount := p_taxable_base * v_tax_rate;
        v_rate_source := 'admin_settings:billing.loaner_rental_tax_rate';
        v_explanation :=
            'Loaner and rental tax was calculated exactly from the pre-tax vehicle charge without rounding.';
    END IF;

    RETURN jsonb_build_object(
        'status', 'billing_tax_resolved',
        'pay_type_rule_id', v_rule.id,
        'pay_type', v_rule.pay_type,
        'taxable_base', p_taxable_base,
        'is_taxable', v_is_taxable,
        'tax_rate', v_tax_rate,
        'tax_amount', v_tax_amount,
        'tax_rate_source', v_rate_source,
        'explanation', v_explanation
    );
END;
$function$;
alter function public.resolve_billing_tax_state(text,numeric) owner to postgres;
revoke all on function public.resolve_billing_tax_state(text,numeric) from public, anon, authenticated, service_role;
grant execute on function public.resolve_billing_tax_state(text,numeric) to service_role;

CREATE OR REPLACE FUNCTION public.create_admin_pay_type_rule_state(p_pay_type text, p_is_taxable boolean, p_default_daily_amount numeric, p_sort_order integer, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id uuid;
    v_access jsonb;
    v_rule public.pay_type_rules%ROWTYPE;
BEGIN
    SELECT app_user.id
    INTO v_user_id
    FROM public.app_users app_user
    WHERE app_user.auth_user_id = auth.uid()
      AND app_user.is_active = true;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Pay type administration access denied'
            USING ERRCODE = '42501';
    END IF;

    v_access :=
        public.get_user_admin_setting_access_state(
            v_user_id,
            'fleet_board.pay_type_colors'
        );

    IF coalesce((v_access ->> 'allowed')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Pay type administration access denied'
            USING ERRCODE = '42501';
    END IF;

    IF p_pay_type IS NULL OR btrim(p_pay_type) = '' THEN
        RAISE EXCEPTION 'Pay type name cannot be blank'
            USING ERRCODE = '22023';
    END IF;

    IF p_is_taxable IS NULL THEN
        RAISE EXCEPTION 'Taxable selection is required'
            USING ERRCODE = '22023';
    END IF;

    IF p_sort_order IS NULL OR p_sort_order < 0 THEN
        RAISE EXCEPTION 'Sort order must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    IF p_default_daily_amount IS NOT NULL
       AND p_default_daily_amount < 0 THEN
        RAISE EXCEPTION 'Default daily amount must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.pay_type_rules rule
        WHERE lower(btrim(rule.pay_type)) = lower(btrim(p_pay_type))
    ) THEN
        RAISE EXCEPTION 'Pay type already exists'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.pay_type_rules (
        pay_type,
        tax_applicable,
        active,
        is_active,
        is_taxable,
        default_daily_amount,
        sort_order,
        description
    )
    VALUES (
        btrim(p_pay_type),
        p_is_taxable,
        true,
        true,
        p_is_taxable,
        p_default_daily_amount,
        p_sort_order,
        nullif(btrim(p_description), '')
    )
    RETURNING *
    INTO v_rule;

    RETURN jsonb_build_object(
        'status', 'admin_pay_type_rule_created',
        'pay_type_rule', jsonb_build_object(
            'pay_type_rule_id', v_rule.id,
            'pay_type', v_rule.pay_type,
            'is_enabled', v_rule.is_active AND coalesce(v_rule.active, false),
            'is_active', v_rule.is_active,
            'active', coalesce(v_rule.active, false),
            'is_taxable', v_rule.is_taxable,
            'tax_applicable', v_rule.tax_applicable,
            'default_daily_amount', v_rule.default_daily_amount,
            'sort_order', v_rule.sort_order,
            'description', v_rule.description
        )
    );
END;
$function$;
alter function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) owner to postgres;
revoke all on function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) from public, anon, authenticated, service_role;
grant execute on function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_admin_pay_type_rule_state(p_pay_type_rule_id uuid, p_is_taxable boolean, p_default_daily_amount numeric, p_sort_order integer, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id uuid;
    v_access jsonb;
    v_rule public.pay_type_rules%ROWTYPE;
BEGIN
    SELECT app_user.id
    INTO v_user_id
    FROM public.app_users app_user
    WHERE app_user.auth_user_id = auth.uid()
      AND app_user.is_active = true;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Pay type administration access denied'
            USING ERRCODE = '42501';
    END IF;

    v_access :=
        public.get_user_admin_setting_access_state(
            v_user_id,
            'fleet_board.pay_type_colors'
        );

    IF coalesce((v_access ->> 'allowed')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Pay type administration access denied'
            USING ERRCODE = '42501';
    END IF;

    IF p_pay_type_rule_id IS NULL THEN
        RAISE EXCEPTION 'Pay type rule ID is required'
            USING ERRCODE = '22023';
    END IF;

    IF p_is_taxable IS NULL THEN
        RAISE EXCEPTION 'Taxable selection is required'
            USING ERRCODE = '22023';
    END IF;

    IF p_sort_order IS NULL OR p_sort_order < 0 THEN
        RAISE EXCEPTION 'Sort order must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    IF p_default_daily_amount IS NOT NULL
       AND p_default_daily_amount < 0 THEN
        RAISE EXCEPTION 'Default daily amount must be zero or greater'
            USING ERRCODE = '22023';
    END IF;

    SELECT rule.*
    INTO v_rule
    FROM public.pay_type_rules rule
    WHERE rule.id = p_pay_type_rule_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pay type rule not found'
            USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.pay_type_rules
    SET
        is_taxable = p_is_taxable,
        tax_applicable = p_is_taxable,
        default_daily_amount = p_default_daily_amount,
        sort_order = p_sort_order,
        description = nullif(btrim(p_description), ''),
        updated_at = clock_timestamp()
    WHERE id = p_pay_type_rule_id
    RETURNING *
    INTO v_rule;

    RETURN jsonb_build_object(
        'status', 'admin_pay_type_rule_updated',
        'pay_type_rule', jsonb_build_object(
            'pay_type_rule_id', v_rule.id,
            'pay_type', v_rule.pay_type,
            'is_enabled', v_rule.is_active AND coalesce(v_rule.active, false),
            'is_active', v_rule.is_active,
            'active', coalesce(v_rule.active, false),
            'is_taxable', v_rule.is_taxable,
            'tax_applicable', v_rule.tax_applicable,
            'default_daily_amount', v_rule.default_daily_amount,
            'sort_order', v_rule.sort_order,
            'description', v_rule.description
        )
    );
END;
$function$;
alter function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) owner to postgres;
revoke all on function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) from public, anon, authenticated, service_role;
grant execute on function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) to authenticated, service_role;

