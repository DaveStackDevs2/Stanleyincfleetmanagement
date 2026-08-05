-- Verified live Extended Warranty mandatory covered-day cap follow-up.
-- Keeps the existing Admin RPC signatures compatible while enforcing provider-level caps
-- and disabling provider-level approval in favor of case-level authorized overrides.

alter table public.extended_warranty_rules alter column covered_days set not null;

alter table public.extended_warranty_rules drop constraint if exists ck_extended_warranty_rules_provider_approval_disabled;
alter table public.extended_warranty_rules add constraint ck_extended_warranty_rules_provider_approval_disabled check (requires_approval = false);

CREATE OR REPLACE FUNCTION public.create_admin_extended_warranty_provider_rule_state(p_provider_name text, p_default_daily_rate numeric, p_covered_days integer, p_requires_approval boolean, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid;
  v_provider public.warranty_providers%ROWTYPE;
  v_rule public.extended_warranty_rules%ROWTYPE;
  v_changed_at timestamptz;
BEGIN
  SELECT au.id
    INTO v_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Extended warranty administration access denied'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.v_user_effective_permissions permission
    WHERE permission.user_id = v_user_id
      AND permission.permission_key = 'user_admin.manage'
  ) THEN
    RAISE EXCEPTION 'Extended warranty administration access denied'
      USING ERRCODE = '42501';
  END IF;

  IF p_provider_name IS NULL OR btrim(p_provider_name) = '' THEN
    RAISE EXCEPTION 'Warranty provider name cannot be blank'
      USING ERRCODE = '22023';
  END IF;

  IF p_default_daily_rate IS NOT NULL
     AND (
       p_default_daily_rate < 0
       OR p_default_daily_rate IN (
         'NaN'::numeric,
         'Infinity'::numeric,
         '-Infinity'::numeric
       )
     )
  THEN
    RAISE EXCEPTION 'Default daily amount must be a finite amount zero or greater'
      USING ERRCODE = '22023';
  END IF;

  IF p_covered_days IS NULL OR p_covered_days <= 0 THEN
    RAISE EXCEPTION 'Covered-day cap must be a positive whole number'
      USING ERRCODE = '22023';
  END IF;

  IF p_requires_approval IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Provider-level approval is not supported; use an authorized case override for coverage extensions'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.warranty_providers provider
    WHERE lower(btrim(provider.name)) = lower(btrim(p_provider_name))
  ) THEN
    RAISE EXCEPTION 'Warranty provider already exists'
      USING ERRCODE = '23505';
  END IF;

  v_changed_at := clock_timestamp();

  BEGIN
    INSERT INTO public.warranty_providers (
      name,
      provider_type,
      is_active,
      default_daily_rate,
      updated_at,
      notes
    )
    VALUES (
      btrim(p_provider_name),
      'extended_warranty',
      true,
      p_default_daily_rate,
      v_changed_at,
      nullif(btrim(p_notes), '')
    )
    RETURNING *
      INTO v_provider;

    INSERT INTO public.extended_warranty_rules (
      provider_id,
      covered_days,
      requires_approval,
      daily_rate,
      is_active,
      updated_at,
      notes
    )
    VALUES (
      v_provider.id,
      p_covered_days,
      false,
      NULL,
      true,
      v_changed_at,
      NULL
    )
    RETURNING *
      INTO v_rule;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION 'Warranty provider already exists'
        USING ERRCODE = '23505';
    WHEN numeric_value_out_of_range THEN
      RAISE EXCEPTION 'Default daily amount is too large'
        USING ERRCODE = '22003';
  END;

  RETURN jsonb_build_object(
    'status', 'admin_extended_warranty_provider_rule_created',
    'provider_rule', jsonb_build_object(
      'provider_id', v_provider.id,
      'provider_name', v_provider.name,
      'provider_type', v_provider.provider_type,
      'provider_is_active', v_provider.is_active,
      'default_daily_rate', v_provider.default_daily_rate,
      'rule_id', v_rule.id,
      'covered_days', v_rule.covered_days,
      'requires_approval', v_rule.requires_approval,
      'rule_daily_rate', v_rule.daily_rate,
      'resolved_daily_rate',
        coalesce(v_rule.daily_rate, v_provider.default_daily_rate),
      'rule_is_active', v_rule.is_active,
      'notes', v_provider.notes,
      'provider_created_at', v_provider.created_at,
      'provider_updated_at', v_provider.updated_at,
      'rule_created_at', v_rule.created_at,
      'rule_updated_at', v_rule.updated_at
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_admin_extended_warranty_provider_rule_state(p_provider_id uuid, p_provider_name text, p_default_daily_rate numeric, p_covered_days integer, p_requires_approval boolean, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid;
  v_provider public.warranty_providers%ROWTYPE;
  v_rule public.extended_warranty_rules%ROWTYPE;
  v_changed_at timestamptz;
BEGIN
  SELECT au.id
    INTO v_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Extended warranty administration access denied'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.v_user_effective_permissions permission
    WHERE permission.user_id = v_user_id
      AND permission.permission_key = 'user_admin.manage'
  ) THEN
    RAISE EXCEPTION 'Extended warranty administration access denied'
      USING ERRCODE = '42501';
  END IF;

  IF p_provider_id IS NULL THEN
    RAISE EXCEPTION 'Warranty provider ID is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_provider_name IS NULL OR btrim(p_provider_name) = '' THEN
    RAISE EXCEPTION 'Warranty provider name cannot be blank'
      USING ERRCODE = '22023';
  END IF;

  IF p_default_daily_rate IS NOT NULL
     AND (
       p_default_daily_rate < 0
       OR p_default_daily_rate IN (
         'NaN'::numeric,
         'Infinity'::numeric,
         '-Infinity'::numeric
       )
     )
  THEN
    RAISE EXCEPTION 'Default daily amount must be a finite amount zero or greater'
      USING ERRCODE = '22023';
  END IF;

  IF p_covered_days IS NULL OR p_covered_days <= 0 THEN
    RAISE EXCEPTION 'Covered-day cap must be a positive whole number'
      USING ERRCODE = '22023';
  END IF;

  IF p_requires_approval IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Provider-level approval is not supported; use an authorized case override for coverage extensions'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_provider
  FROM public.warranty_providers
  WHERE id = p_provider_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Warranty provider not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT *
    INTO v_rule
  FROM public.extended_warranty_rules
  WHERE provider_id = p_provider_id
    AND is_active = true
  ORDER BY updated_at DESC, created_at DESC, id
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active extended warranty rule not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.warranty_providers provider
    WHERE provider.id <> p_provider_id
      AND lower(btrim(provider.name)) = lower(btrim(p_provider_name))
  ) THEN
    RAISE EXCEPTION 'Warranty provider already exists'
      USING ERRCODE = '23505';
  END IF;

  v_changed_at := clock_timestamp();

  BEGIN
    UPDATE public.warranty_providers
    SET
      name = btrim(p_provider_name),
      default_daily_rate = p_default_daily_rate,
      notes = nullif(btrim(p_notes), ''),
      updated_at = v_changed_at
    WHERE id = p_provider_id
    RETURNING *
      INTO v_provider;

    UPDATE public.extended_warranty_rules
    SET
      covered_days = p_covered_days,
      requires_approval = false,
      daily_rate = NULL,
      updated_at = v_changed_at
    WHERE id = v_rule.id
    RETURNING *
      INTO v_rule;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION 'Warranty provider already exists'
        USING ERRCODE = '23505';
    WHEN numeric_value_out_of_range THEN
      RAISE EXCEPTION 'Default daily amount is too large'
        USING ERRCODE = '22003';
  END;

  RETURN jsonb_build_object(
    'status', 'admin_extended_warranty_provider_rule_updated',
    'provider_rule', jsonb_build_object(
      'provider_id', v_provider.id,
      'provider_name', v_provider.name,
      'provider_type', v_provider.provider_type,
      'provider_is_active', v_provider.is_active,
      'default_daily_rate', v_provider.default_daily_rate,
      'rule_id', v_rule.id,
      'covered_days', v_rule.covered_days,
      'requires_approval', v_rule.requires_approval,
      'rule_daily_rate', v_rule.daily_rate,
      'resolved_daily_rate',
        coalesce(v_rule.daily_rate, v_provider.default_daily_rate),
      'rule_is_active', v_rule.is_active,
      'notes', v_provider.notes,
      'provider_created_at', v_provider.created_at,
      'provider_updated_at', v_provider.updated_at,
      'rule_created_at', v_rule.created_at,
      'rule_updated_at', v_rule.updated_at
    )
  );
END;
$function$;

alter function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) owner to postgres;
alter function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) owner to postgres;

revoke all on function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) from public, anon, authenticated;
revoke all on function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) from public, anon, authenticated;

grant execute on function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) to authenticated, service_role;
grant execute on function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) to authenticated, service_role;
