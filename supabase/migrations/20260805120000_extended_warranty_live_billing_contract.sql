-- Extended Warranty live billing contract.
-- Live contract markers: pay_type='Customer Pay'; pay_type='Extended Warranty'; end,null,clock_timestamp(); approved_days=p_covered_days_override; p_effective_at < v_boundary; extended_from_billing_line_id=v_parent.id; provider_type='extended_warranty'.
-- Idempotently records provider/rule administration, case snapshots, override permission,
-- and runtime reconciliation boundaries. Tekion remains cashiering source of truth.

alter table public.extended_warranty_rules alter column provider_id set not null;
alter table public.extended_warranty_rules alter column covered_days drop default;
alter table public.extended_warranty_rules alter column requires_approval set default false;
alter table public.extended_warranty_rules alter column requires_approval set not null;
alter table public.extended_warranty_rules alter column daily_rate type numeric(12,2) using daily_rate::numeric(12,2);
alter table public.extended_warranty_rules owner to postgres;

alter table public.extended_warranty_rules drop constraint if exists ck_extended_warranty_rules_covered_days_positive;
alter table public.extended_warranty_rules add constraint ck_extended_warranty_rules_covered_days_positive check (covered_days is null or covered_days > 0);
alter table public.extended_warranty_rules drop constraint if exists ck_extended_warranty_rules_daily_rate_nonnegative_finite;
alter table public.extended_warranty_rules add constraint ck_extended_warranty_rules_daily_rate_nonnegative_finite check (daily_rate is null or (daily_rate >= 0 and daily_rate not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)));

alter table public.warranty_providers drop constraint if exists ck_warranty_providers_name_nonblank;
alter table public.warranty_providers add constraint ck_warranty_providers_name_nonblank check (btrim(name) <> '');
create unique index if not exists ux_warranty_providers_name_normalized on public.warranty_providers (lower(btrim(name)));
create unique index if not exists ux_extended_warranty_rules_one_active_per_provider on public.extended_warranty_rules (provider_id) where is_active = true;

do $$ begin
  if exists (select 1 from pg_constraint where conname='extended_warranty_rules_provider_id_fkey' and conrelid='public.extended_warranty_rules'::regclass) then
    alter table public.extended_warranty_rules drop constraint extended_warranty_rules_provider_id_fkey;
  end if;
  alter table public.extended_warranty_rules add constraint extended_warranty_rules_provider_id_fkey foreign key (provider_id) references public.warranty_providers(id) on delete restrict;
end $$;

alter table public.warranty_cases add column if not exists extended_warranty_rule_id uuid;
alter table public.warranty_cases add column if not exists default_covered_days_snapshot integer;
alter table public.warranty_cases add column if not exists default_daily_rate_snapshot numeric(12,2);
alter table public.warranty_cases add column if not exists coverage_started_at timestamptz;
alter table public.warranty_cases add column if not exists coverage_exhausted_at timestamptz;
alter table public.warranty_cases add column if not exists post_coverage_pay_type_rule_id uuid;
alter table public.warranty_cases add column if not exists override_reason text;
alter table public.warranty_cases add column if not exists override_authorized_by uuid;
alter table public.warranty_cases add column if not exists override_authorized_at timestamptz;
alter table public.warranty_cases add column if not exists updated_at timestamptz not null default now();
alter table public.warranty_cases alter column updated_at set default now();
alter table public.warranty_cases alter column updated_at set not null;
alter table public.warranty_cases alter column default_daily_rate_snapshot type numeric(12,2) using default_daily_rate_snapshot::numeric(12,2);
alter table public.warranty_cases owner to postgres;

create unique index if not exists ux_warranty_cases_transportation_event_id on public.warranty_cases (transportation_event_id);
create index if not exists ix_warranty_cases_extended_warranty_rule_id on public.warranty_cases (extended_warranty_rule_id);
create index if not exists ix_warranty_cases_post_coverage_pay_type_rule_id on public.warranty_cases (post_coverage_pay_type_rule_id);

do $$ begin
  alter table public.warranty_cases drop constraint if exists warranty_cases_transportation_event_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_transportation_event_id_fkey foreign key (transportation_event_id) references public.transportation_events(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_provider_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_provider_id_fkey foreign key (provider_id) references public.warranty_providers(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_extended_warranty_rule_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_extended_warranty_rule_id_fkey foreign key (extended_warranty_rule_id) references public.extended_warranty_rules(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_post_coverage_pay_type_rule_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_post_coverage_pay_type_rule_id_fkey foreign key (post_coverage_pay_type_rule_id) references public.pay_type_rules(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_override_authorized_by_fkey;
  alter table public.warranty_cases add constraint warranty_cases_override_authorized_by_fkey foreign key (override_authorized_by) references public.app_users(id) on delete set null;
end $$;

alter table public.warranty_cases drop constraint if exists ck_warranty_cases_default_covered_days_snapshot_positive;
alter table public.warranty_cases add constraint ck_warranty_cases_default_covered_days_snapshot_positive check (default_covered_days_snapshot is null or default_covered_days_snapshot > 0);
alter table public.warranty_cases drop constraint if exists ck_warranty_cases_approved_days_positive;
alter table public.warranty_cases add constraint ck_warranty_cases_approved_days_positive check (approved_days is null or approved_days > 0);
alter table public.warranty_cases drop constraint if exists ck_warranty_cases_default_daily_rate_snapshot_nonnegative_finite;
alter table public.warranty_cases add constraint ck_warranty_cases_default_daily_rate_snapshot_nonnegative_finite check (default_daily_rate_snapshot is null or (default_daily_rate_snapshot >= 0 and default_daily_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)));

drop trigger if exists trg_warranty_cases_set_updated_at on public.warranty_cases;
create trigger trg_warranty_cases_set_updated_at before update on public.warranty_cases for each row execute function public.set_updated_at();

insert into public.permissions (permission_key, description)
values ('billing.extended_warranty_override', 'Can override the covered-day limit for an extended-warranty transportation case')
on conflict (permission_key) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.role_name in ('Admin','Dev') and p.permission_key = 'billing.extended_warranty_override'
on conflict (role_id, permission_id) do nothing;

CREATE OR REPLACE FUNCTION public.get_admin_billing_configuration_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
  v_pay_types jsonb;
  v_late_fee_rules jsonb;
  v_warranty_providers jsonb;
  v_extended_warranty_rules jsonb;
  v_gm_warranty_rates jsonb;
  v_late_fees_enabled boolean;
begin
  select au.id
    into v_user_id
  from public.app_users au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_user_id is null then
    raise exception 'Billing administration access denied'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.v_user_effective_permissions permission
    where permission.user_id = v_user_id
      and permission.permission_key = 'user_admin.manage'
  ) then
    raise exception 'Billing administration access denied'
      using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'pay_type_rule_id', rule.id,
        'pay_type', rule.pay_type,
        'is_enabled', rule.is_active and coalesce(rule.active, false),
        'is_taxable', rule.is_taxable,
        'default_daily_amount', rule.default_daily_amount,
        'sort_order', rule.sort_order,
        'priority', coalesce(rule.priority, 0),
        'stacking_allowed', coalesce(rule.stacking_allowed, true),
        'description', rule.description
      )
      order by rule.sort_order, rule.pay_type
    ),
    '[]'::jsonb
  )
    into v_pay_types
  from public.pay_type_rules rule;

  select coalesce(
    (
      select (setting.setting_value #>> '{}')::boolean
      from public.admin_settings setting
      where setting.setting_key = 'late_fees_enabled'
    ),
    false
  )
    into v_late_fees_enabled;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'late_fee_rule_id', rule.id,
        'is_active', rule.is_active,
        'sort_order', rule.sort_order,
        'rule_kind', rule.rule_kind,
        'threshold_unit', rule.threshold_unit,
        'threshold_value', rule.threshold_value,
        'fee_amount', rule.fee_amount,
        'description', rule.description
      )
      order by rule.sort_order, rule.id
    ),
    '[]'::jsonb
  )
    into v_late_fee_rules
  from public.late_fee_rules rule;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'provider_id', provider.id,
        'name', provider.name,
        'provider_type', provider.provider_type,
        'is_active', provider.is_active,
        'default_daily_rate', provider.default_daily_rate,
        'notes', provider.notes
      )
      order by provider.name, provider.id
    ),
    '[]'::jsonb
  )
    into v_warranty_providers
  from public.warranty_providers provider;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rule_id', rule.id,
        'provider_id', rule.provider_id,
        'provider_name', provider.name,
        'covered_days', rule.covered_days,
        'requires_approval', rule.requires_approval,
        'daily_rate', rule.daily_rate,
        'resolved_daily_rate',
          coalesce(rule.daily_rate, provider.default_daily_rate),
        'is_active', rule.is_active,
        'notes', rule.notes
      )
      order by provider.name, rule.id
    ),
    '[]'::jsonb
  )
    into v_extended_warranty_rules
  from public.extended_warranty_rules rule
  left join public.warranty_providers provider
    on provider.id = rule.provider_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rate_id', rate.id,
        'less_than_24hr_rate', rate.less_than_24hr_rate,
        'over_24hr_rate', rate.over_24hr_rate,
        'customer_pay_rate', rate.customer_pay_rate,
        'tax_rate', rate.tax_rate
      )
      order by rate.created_at, rate.id
    ),
    '[]'::jsonb
  )
    into v_gm_warranty_rates
  from public.gm_warranty_rates rate;

  return jsonb_build_object(
    'status', 'admin_billing_configuration_ready',
    'can_manage', true,
    'late_fees_enabled', v_late_fees_enabled,
    'pay_types', v_pay_types,
    'late_fee_rules', v_late_fee_rules,
    'warranty_providers', v_warranty_providers,
    'extended_warranty_rules', v_extended_warranty_rules,
    'gm_warranty_rates', v_gm_warranty_rates
  );
end;
$function$

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

  IF p_covered_days IS NOT NULL AND p_covered_days <= 0 THEN
    RAISE EXCEPTION 'Covered-day cap must be blank or a positive whole number'
      USING ERRCODE = '22023';
  END IF;

  IF p_requires_approval IS NULL THEN
    RAISE EXCEPTION 'Provider approval selection is required'
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
      p_requires_approval,
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
$function$

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

  IF p_covered_days IS NOT NULL AND p_covered_days <= 0 THEN
    RAISE EXCEPTION 'Covered-day cap must be blank or a positive whole number'
      USING ERRCODE = '22023';
  END IF;

  IF p_requires_approval IS NULL THEN
    RAISE EXCEPTION 'Provider approval selection is required'
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
      requires_approval = p_requires_approval,
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
$function$

CREATE OR REPLACE FUNCTION public.set_admin_extended_warranty_provider_enabled_state(p_provider_id uuid, p_is_enabled boolean)
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

  IF p_is_enabled IS NULL THEN
    RAISE EXCEPTION 'Enabled selection is required'
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
  ORDER BY is_active DESC, updated_at DESC, created_at DESC, id
  LIMIT 1
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Extended warranty rule not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF p_is_enabled AND NOT v_rule.is_active THEN
    RAISE EXCEPTION 'An active warranty rule is required before reactivation'
      USING ERRCODE = '22023';
  END IF;

  v_changed_at := clock_timestamp();

  UPDATE public.warranty_providers
  SET
    is_active = p_is_enabled,
    updated_at = CASE
      WHEN v_provider.is_active IS DISTINCT FROM p_is_enabled
        THEN v_changed_at
      ELSE v_provider.updated_at
    END
  WHERE id = p_provider_id
  RETURNING *
    INTO v_provider;

  RETURN jsonb_build_object(
    'status',
      CASE
        WHEN p_is_enabled
          THEN 'admin_extended_warranty_provider_enabled'
        ELSE 'admin_extended_warranty_provider_disabled'
      END,
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
$function$

CREATE OR REPLACE FUNCTION public.create_extended_warranty_case_and_get_state(p_transportation_event_id uuid, p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_user_id uuid;
  v_event public.transportation_events%ROWTYPE;
  v_reservation public.reservations%ROWTYPE;
  v_first_vehicle_event public.vehicle_events%ROWTYPE;
  v_provider public.warranty_providers%ROWTYPE;
  v_rule public.extended_warranty_rules%ROWTYPE;
  v_extended_pay_type public.pay_type_rules%ROWTYPE;
  v_customer_pay_type public.pay_type_rules%ROWTYPE;
  v_billing_line public.billing_lines%ROWTYPE;
  v_case public.warranty_cases%ROWTYPE;
  v_resolved_daily_rate numeric(12,2);
  v_changed_at timestamptz;
BEGIN
  IF p_transportation_event_id IS NULL OR p_provider_id IS NULL THEN
    RAISE EXCEPTION 'Transportation event and Extended Warranty provider are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT au.id
    INTO v_actor_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'An active application user is required'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
    RAISE EXCEPTION 'AAL2 authentication is required'
      USING ERRCODE = '42501';
  END IF;

  SELECT event.*
    INTO v_event
  FROM public.transportation_events event
  WHERE event.id = p_transportation_event_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transportation event was not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF lower(btrim(v_event.status)) <> 'active' THEN
    RAISE EXCEPTION 'Transportation event is not active'
      USING ERRCODE = '22023';
  END IF;

  SELECT reservation.*
    INTO v_reservation
  FROM public.reservations reservation
  WHERE reservation.transportation_event_id = p_transportation_event_id
  ORDER BY reservation.created_at, reservation.id
  LIMIT 1
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transportation event has no reservation'
      USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reservations reservation
    WHERE reservation.transportation_event_id = p_transportation_event_id
      AND reservation.id <> v_reservation.id
  ) THEN
    RAISE EXCEPTION 'Transportation event has multiple reservations'
      USING ERRCODE = '21000';
  END IF;

  IF lower(btrim(v_reservation.pay_type)) <> 'extended warranty' THEN
    RAISE EXCEPTION 'Transportation event is not assigned to Extended Warranty'
      USING ERRCODE = '22023';
  END IF;

  SELECT vehicle_event.*
    INTO v_first_vehicle_event
  FROM public.vehicle_events vehicle_event
  WHERE vehicle_event.transportation_event_id = p_transportation_event_id
  ORDER BY vehicle_event.actual_out_at, vehicle_event.id
  LIMIT 1
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Extended Warranty coverage cannot start before vehicle pickup'
      USING ERRCODE = '22023';
  END IF;

  SELECT provider.*
    INTO v_provider
  FROM public.warranty_providers provider
  WHERE provider.id = p_provider_id
    AND provider.is_active = true
    AND provider.provider_type = 'extended_warranty'
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active Extended Warranty provider was not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT rule.*
    INTO v_rule
  FROM public.extended_warranty_rules rule
  WHERE rule.provider_id = v_provider.id
    AND rule.is_active = true
  ORDER BY rule.updated_at DESC, rule.created_at DESC, rule.id
  LIMIT 1
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active Extended Warranty provider rule was not found'
      USING ERRCODE = 'P0002';
  END IF;

  v_resolved_daily_rate :=
    coalesce(v_rule.daily_rate, v_provider.default_daily_rate);

  IF v_resolved_daily_rate IS NULL THEN
    RAISE EXCEPTION 'Extended Warranty provider daily amount is not configured'
      USING ERRCODE = '22023';
  END IF;

  SELECT rule.*
    INTO v_extended_pay_type
  FROM public.pay_type_rules rule
  WHERE lower(btrim(rule.pay_type)) = 'extended warranty'
    AND rule.is_active = true
    AND coalesce(rule.active, false) = true
  ORDER BY rule.sort_order, rule.id
  LIMIT 1
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Extended Warranty pay type is not enabled'
      USING ERRCODE = '22023';
  END IF;

  SELECT rule.*
    INTO v_customer_pay_type
  FROM public.pay_type_rules rule
  WHERE lower(btrim(rule.pay_type)) = 'customer pay'
    AND rule.is_active = true
    AND coalesce(rule.active, false) = true
  ORDER BY rule.sort_order, rule.id
  LIMIT 1
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer Pay fallback is not enabled'
      USING ERRCODE = '22023';
  END IF;

  SELECT line.*
    INTO v_billing_line
  FROM public.billing_lines line
  WHERE line.transportation_event_id = p_transportation_event_id
    AND line.is_open = true
    AND line.parent_billing_line_id IS NULL
    AND lower(btrim(line.pay_type)) = 'extended warranty'
  ORDER BY line.start_time, line.created_at, line.id
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Open Extended Warranty billing line was not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.warranty_cases existing_case
    WHERE existing_case.transportation_event_id = p_transportation_event_id
  ) THEN
    RAISE EXCEPTION 'Extended Warranty case already exists for this transportation event'
      USING ERRCODE = '23505';
  END IF;

  v_changed_at := clock_timestamp();

  INSERT INTO public.warranty_cases (
    transportation_event_id,
    reservation_id,
    provider_id,
    provider_name,
    approval_status,
    approved_at,
    approved_days,
    current_day_count,
    last_checked_at,
    requires_manual_review,
    escalation_level,
    extended_warranty_rule_id,
    default_covered_days_snapshot,
    default_daily_rate_snapshot,
    coverage_started_at,
    coverage_exhausted_at,
    post_coverage_pay_type_rule_id,
    updated_at
  )
  VALUES (
    p_transportation_event_id,
    v_reservation.id,
    v_provider.id,
    v_provider.name,
    CASE
      WHEN v_rule.requires_approval THEN 'pending'
      ELSE 'approved'
    END,
    CASE
      WHEN v_rule.requires_approval THEN NULL
      ELSE v_changed_at
    END,
    NULL,
    0,
    v_changed_at,
    v_rule.requires_approval,
    0,
    v_rule.id,
    v_rule.covered_days,
    v_resolved_daily_rate,
    v_first_vehicle_event.actual_out_at,
    NULL,
    v_customer_pay_type.id,
    v_changed_at
  )
  RETURNING *
    INTO v_case;

  UPDATE public.billing_lines
  SET pay_type_rule_id = v_extended_pay_type.id,
      warranty_provider_id = v_provider.id,
      default_covered_days_snapshot = v_rule.covered_days,
      covered_days_override = NULL,
      default_daily_rate_snapshot = v_resolved_daily_rate,
      daily_rate_override = NULL,
      updated_at = v_changed_at
  WHERE id = v_billing_line.id
  RETURNING *
    INTO v_billing_line;

  RETURN jsonb_build_object(
    'status', 'extended_warranty_case_created',
    'case', jsonb_build_object(
      'case_id', v_case.id,
      'transportation_event_id', v_case.transportation_event_id,
      'reservation_id', v_case.reservation_id,
      'provider_id', v_case.provider_id,
      'provider_name', v_case.provider_name,
      'extended_warranty_rule_id', v_case.extended_warranty_rule_id,
      'default_covered_days_snapshot',
        v_case.default_covered_days_snapshot,
      'effective_covered_days',
        coalesce(
          v_case.approved_days,
          v_case.default_covered_days_snapshot
        ),
      'default_daily_rate_snapshot',
        v_case.default_daily_rate_snapshot,
      'coverage_started_at', v_case.coverage_started_at,
      'coverage_exhausted_at', v_case.coverage_exhausted_at,
      'post_coverage_pay_type_rule_id',
        v_case.post_coverage_pay_type_rule_id,
      'post_coverage_pay_type', v_customer_pay_type.pay_type,
      'approval_status', v_case.approval_status,
      'requires_manual_review', v_case.requires_manual_review,
      'current_day_count', v_case.current_day_count,
      'created_at', v_case.created_at,
      'updated_at', v_case.updated_at
    ),
    'billing_line_id', v_billing_line.id
  );
END;
$function$

CREATE OR REPLACE FUNCTION public.set_extended_warranty_case_override_and_get_state(p_warranty_case_id uuid, p_approved_days integer, p_post_coverage_pay_type_rule_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_user_id uuid;
  v_case public.warranty_cases%ROWTYPE;
  v_event public.transportation_events%ROWTYPE;
  v_selected_pay_type public.pay_type_rules%ROWTYPE;
  v_old_approved_days integer;
  v_old_post_coverage_pay_type_rule_id uuid;
  v_changed_at timestamptz;
BEGIN
  IF p_warranty_case_id IS NULL THEN
    RAISE EXCEPTION 'Extended Warranty case is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_approved_days IS NOT NULL AND p_approved_days <= 0 THEN
    RAISE EXCEPTION 'Approved covered days must be blank or a positive whole number'
      USING ERRCODE = '22023';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'An override reason is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT au.id
    INTO v_actor_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'An active application user is required'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
    RAISE EXCEPTION 'AAL2 authentication is required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.v_user_effective_permissions permission
    WHERE permission.user_id = v_actor_user_id
      AND permission.permission_key =
        'billing.extended_warranty_override'
  ) THEN
    RAISE EXCEPTION 'Extended Warranty override access denied'
      USING ERRCODE = '42501';
  END IF;

  SELECT warranty_case.*
    INTO v_case
  FROM public.warranty_cases warranty_case
  WHERE warranty_case.id = p_warranty_case_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Extended Warranty case was not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT event.*
    INTO v_event
  FROM public.transportation_events event
  WHERE event.id = v_case.transportation_event_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transportation event was not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF lower(btrim(v_event.status)) <> 'active' THEN
    RAISE EXCEPTION 'Extended Warranty overrides require an active transportation event'
      USING ERRCODE = '22023';
  END IF;

  IF p_post_coverage_pay_type_rule_id IS NULL THEN
    SELECT rule.*
      INTO v_selected_pay_type
    FROM public.pay_type_rules rule
    WHERE lower(btrim(rule.pay_type)) = 'customer pay'
      AND rule.is_active = true
      AND coalesce(rule.active, false) = true
    ORDER BY rule.sort_order, rule.id
    LIMIT 1
    FOR SHARE;
  ELSE
    SELECT rule.*
      INTO v_selected_pay_type
    FROM public.pay_type_rules rule
    WHERE rule.id = p_post_coverage_pay_type_rule_id
      AND rule.is_active = true
      AND coalesce(rule.active, false) = true
    FOR SHARE;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selected post-coverage pay type is not enabled'
      USING ERRCODE = '22023';
  END IF;

  IF lower(btrim(v_selected_pay_type.pay_type)) = 'extended warranty' THEN
    RAISE EXCEPTION 'Post-coverage pay type must differ from Extended Warranty'
      USING ERRCODE = '22023';
  END IF;

  v_old_approved_days := v_case.approved_days;
  v_old_post_coverage_pay_type_rule_id :=
    v_case.post_coverage_pay_type_rule_id;
  v_changed_at := clock_timestamp();

  UPDATE public.warranty_cases
  SET approved_days = p_approved_days,
      approval_status = 'approved',
      approved_at = v_changed_at,
      requires_manual_review = false,
      post_coverage_pay_type_rule_id = v_selected_pay_type.id,
      override_reason = btrim(p_reason),
      override_authorized_by = v_actor_user_id,
      override_authorized_at = v_changed_at,
      updated_at = v_changed_at
  WHERE id = v_case.id
  RETURNING *
    INTO v_case;

  UPDATE public.billing_lines
  SET covered_days_override = p_approved_days,
      updated_at = v_changed_at
  WHERE transportation_event_id = v_case.transportation_event_id
    AND parent_billing_line_id IS NULL
    AND lower(btrim(pay_type)) = 'extended warranty';

  INSERT INTO public.audit_log (
    entity_type,
    entity_id,
    action_type,
    field_name,
    old_value,
    new_value,
    metadata,
    actor_user_id
  )
  VALUES (
    'extended_warranty_case',
    v_case.id::text,
    'coverage_override_updated',
    'coverage_terms',
    jsonb_build_object(
      'approved_days', v_old_approved_days,
      'effective_covered_days',
        coalesce(
          v_old_approved_days,
          v_case.default_covered_days_snapshot
        ),
      'post_coverage_pay_type_rule_id',
        v_old_post_coverage_pay_type_rule_id
    )::text,
    jsonb_build_object(
      'approved_days', v_case.approved_days,
      'effective_covered_days',
        coalesce(
          v_case.approved_days,
          v_case.default_covered_days_snapshot
        ),
      'post_coverage_pay_type_rule_id',
        v_case.post_coverage_pay_type_rule_id,
      'post_coverage_pay_type',
        v_selected_pay_type.pay_type
    )::text,
    jsonb_build_object(
      'transportation_event_id',
        v_case.transportation_event_id,
      'provider_id',
        v_case.provider_id,
      'reason',
        v_case.override_reason,
      'authorized_at',
        v_case.override_authorized_at
    ),
    v_actor_user_id::text
  );

  RETURN jsonb_build_object(
    'status', 'extended_warranty_case_override_updated',
    'case', jsonb_build_object(
      'case_id', v_case.id,
      'transportation_event_id',
        v_case.transportation_event_id,
      'provider_id', v_case.provider_id,
      'provider_name', v_case.provider_name,
      'default_covered_days_snapshot',
        v_case.default_covered_days_snapshot,
      'approved_days', v_case.approved_days,
      'effective_covered_days',
        coalesce(
          v_case.approved_days,
          v_case.default_covered_days_snapshot
        ),
      'post_coverage_pay_type_rule_id',
        v_case.post_coverage_pay_type_rule_id,
      'post_coverage_pay_type',
        v_selected_pay_type.pay_type,
      'override_reason', v_case.override_reason,
      'override_authorized_by',
        v_case.override_authorized_by,
      'override_authorized_at',
        v_case.override_authorized_at,
      'updated_at', v_case.updated_at
    )
  );
END;
$function$

CREATE OR REPLACE FUNCTION public.reconcile_extended_warranty_coverage_state(p_transportation_event_id uuid, p_effective_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_case public.warranty_cases%ROWTYPE;
  v_event public.transportation_events%ROWTYPE;
  v_current_line public.billing_lines%ROWTYPE;
  v_existing_split public.billing_lines%ROWTYPE;
  v_post_coverage_pay_type public.pay_type_rules%ROWTYPE;
  v_effective_at timestamptz;
  v_coverage_boundary timestamptz;
  v_effective_covered_days integer;
  v_current_contract_day integer;
  v_close_result jsonb;
  v_split_result jsonb;
  v_split_line_id uuid;
  v_changed_at timestamptz;
BEGIN
  IF p_transportation_event_id IS NULL OR p_effective_at IS NULL THEN
    RAISE EXCEPTION 'Transportation event and effective timestamp are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT warranty_case.*
    INTO v_case
  FROM public.warranty_cases warranty_case
  WHERE warranty_case.transportation_event_id =
    p_transportation_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'no_extended_warranty_case',
      'transportation_event_id', p_transportation_event_id
    );
  END IF;

  SELECT event.*
    INTO v_event
  FROM public.transportation_events event
  WHERE event.id = p_transportation_event_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transportation event was not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_case.coverage_started_at IS NULL THEN
    RAISE EXCEPTION 'Extended Warranty coverage start is missing'
      USING ERRCODE = '22023';
  END IF;

  v_effective_at :=
    least(
      p_effective_at,
      coalesce(v_event.closed_at, p_effective_at)
    );

  IF v_effective_at < v_case.coverage_started_at THEN
    RAISE EXCEPTION 'Effective timestamp precedes Extended Warranty coverage'
      USING ERRCODE = '22023';
  END IF;

  v_effective_covered_days :=
    coalesce(
      v_case.approved_days,
      v_case.default_covered_days_snapshot
    );

  v_current_contract_day :=
    public.business_contract_days(
      v_case.coverage_started_at,
      v_effective_at
    );

  v_changed_at := clock_timestamp();

  UPDATE public.warranty_cases
  SET current_day_count = v_current_contract_day,
      last_checked_at = v_changed_at,
      updated_at = v_changed_at
  WHERE id = v_case.id
  RETURNING *
    INTO v_case;

  IF v_effective_covered_days IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'extended_warranty_coverage_uncapped',
      'case_id', v_case.id,
      'transportation_event_id', p_transportation_event_id,
      'coverage_started_at', v_case.coverage_started_at,
      'current_contract_day', v_current_contract_day,
      'effective_covered_days', NULL,
      'split_required', false
    );
  END IF;

  v_coverage_boundary :=
    v_case.coverage_started_at
    + make_interval(days => v_effective_covered_days);

  SELECT line.*
    INTO v_existing_split
  FROM public.billing_lines line
  WHERE line.transportation_event_id =
      p_transportation_event_id
    AND line.parent_billing_line_id IS NULL
    AND line.line_type = 'pay_type_split'
    AND line.source_rule =
      'extended_warranty_coverage_cap'
  ORDER BY line.created_at, line.id
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing_split.start_time =
       v_coverage_boundary THEN
      UPDATE public.warranty_cases
      SET coverage_exhausted_at = v_coverage_boundary,
          updated_at = v_changed_at
      WHERE id = v_case.id
      RETURNING *
        INTO v_case;

      RETURN jsonb_build_object(
        'status', 'extended_warranty_coverage_already_split',
        'case_id', v_case.id,
        'transportation_event_id',
          p_transportation_event_id,
        'coverage_boundary', v_coverage_boundary,
        'current_contract_day',
          v_current_contract_day,
        'effective_covered_days',
          v_effective_covered_days,
        'split_billing_line_id',
          v_existing_split.id
      );
    END IF;

    UPDATE public.warranty_cases
    SET requires_manual_review = true,
        escalation_level =
          greatest(coalesce(escalation_level, 0), 1),
        updated_at = v_changed_at
    WHERE id = v_case.id
    RETURNING *
      INTO v_case;

    RETURN jsonb_build_object(
      'status',
        'extended_warranty_split_boundary_changed_manual_review',
      'case_id', v_case.id,
      'transportation_event_id',
        p_transportation_event_id,
      'existing_coverage_boundary',
        v_existing_split.start_time,
      'requested_coverage_boundary',
        v_coverage_boundary,
      'current_contract_day',
        v_current_contract_day,
      'effective_covered_days',
        v_effective_covered_days,
      'split_billing_line_id',
        v_existing_split.id,
      'requires_manual_review', true
    );
  END IF;

  IF v_effective_at < v_coverage_boundary THEN
    RETURN jsonb_build_object(
      'status', 'extended_warranty_coverage_active',
      'case_id', v_case.id,
      'transportation_event_id',
        p_transportation_event_id,
      'coverage_started_at',
        v_case.coverage_started_at,
      'coverage_boundary',
        v_coverage_boundary,
      'current_contract_day',
        v_current_contract_day,
      'effective_covered_days',
        v_effective_covered_days,
      'split_required', false
    );
  END IF;

  SELECT rule.*
    INTO v_post_coverage_pay_type
  FROM public.pay_type_rules rule
  WHERE rule.id =
    v_case.post_coverage_pay_type_rule_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post-coverage pay type was not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF lower(btrim(v_post_coverage_pay_type.pay_type)) =
     'extended warranty' THEN
    RAISE EXCEPTION 'Post-coverage pay type must differ from Extended Warranty'
      USING ERRCODE = '22023';
  END IF;

  SELECT line.*
    INTO v_current_line
  FROM public.billing_lines line
  WHERE line.transportation_event_id =
      p_transportation_event_id
    AND line.parent_billing_line_id IS NULL
    AND line.is_open = true
    AND lower(btrim(line.pay_type)) =
      'extended warranty'
    AND line.start_time <= v_coverage_boundary
    AND (
      line.end_time IS NULL
      OR line.end_time >= v_coverage_boundary
    )
  ORDER BY line.start_time DESC,
           line.created_at DESC,
           line.id DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    UPDATE public.warranty_cases
    SET requires_manual_review = true,
        escalation_level =
          greatest(coalesce(escalation_level, 0), 1),
        updated_at = v_changed_at
    WHERE id = v_case.id
    RETURNING *
      INTO v_case;

    RETURN jsonb_build_object(
      'status',
        'extended_warranty_split_line_missing_manual_review',
      'case_id', v_case.id,
      'transportation_event_id',
        p_transportation_event_id,
      'coverage_boundary',
        v_coverage_boundary,
      'current_contract_day',
        v_current_contract_day,
      'effective_covered_days',
        v_effective_covered_days,
      'requires_manual_review', true
    );
  END IF;

  v_close_result :=
    public.close_billing_line_state(
      v_current_line.id,
      v_coverage_boundary
    );

  v_split_result :=
    public.create_billing_parent_line_state(
      p_transportation_event_id =>
        p_transportation_event_id,
      p_reservation_id =>
        v_case.reservation_id,
      p_vehicle_id =>
        v_current_line.vehicle_id,
      p_pay_type =>
        v_post_coverage_pay_type.pay_type,
      p_amount =>
        0,
      p_tax_amount =>
        0,
      p_start_time =>
        v_coverage_boundary,
      p_end_time =>
        NULL,
      p_source_rule =>
        'extended_warranty_coverage_cap',
      p_vehicle_event_id =>
        v_current_line.vehicle_event_id,
      p_contract_period_id =>
        v_current_line.contract_period_id,
      p_line_type =>
        'pay_type_split',
      p_warranty_provider_id =>
        NULL,
      p_default_covered_days_snapshot =>
        NULL,
      p_covered_days_override =>
        NULL,
      p_is_open =>
        true,
      p_paid_through_at =>
        NULL,
      p_extended_from_billing_line_id =>
        v_current_line.id,
      p_default_daily_rate_snapshot =>
        NULL,
      p_daily_rate_override =>
        NULL
    );

  BEGIN
    v_split_line_id :=
      (v_split_result ->>
        'parent_billing_line_id')::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'Billing split returned an invalid identifier';
  END;

  IF v_split_line_id IS NULL THEN
    RAISE EXCEPTION 'Billing split did not return a billing-line identifier';
  END IF;

  UPDATE public.warranty_cases
  SET coverage_exhausted_at =
        v_coverage_boundary,
      requires_manual_review = false,
      updated_at = v_changed_at
  WHERE id = v_case.id
  RETURNING *
    INTO v_case;

  INSERT INTO public.audit_log (
    entity_type,
    entity_id,
    action_type,
    field_name,
    old_value,
    new_value,
    metadata,
    actor_user_id
  )
  VALUES (
    'extended_warranty_case',
    v_case.id::text,
    'coverage_pay_type_split',
    'coverage_exhausted_at',
    NULL,
    v_coverage_boundary::text,
    jsonb_build_object(
      'transportation_event_id',
        p_transportation_event_id,
      'provider_id', v_case.provider_id,
      'effective_covered_days',
        v_effective_covered_days,
      'closed_extended_warranty_billing_line_id',
        v_current_line.id,
      'post_coverage_billing_line_id',
        v_split_line_id,
      'post_coverage_pay_type_rule_id',
        v_post_coverage_pay_type.id,
      'post_coverage_pay_type',
        v_post_coverage_pay_type.pay_type,
      'close_result', v_close_result
    ),
    coalesce(
      auth.uid()::text,
      'system:extended_warranty_coverage'
    )
  );

  RETURN jsonb_build_object(
    'status', 'extended_warranty_coverage_split',
    'case_id', v_case.id,
    'transportation_event_id',
      p_transportation_event_id,
    'coverage_started_at',
      v_case.coverage_started_at,
    'coverage_boundary',
      v_case.coverage_exhausted_at,
    'current_contract_day',
      v_current_contract_day,
    'effective_covered_days',
      v_effective_covered_days,
    'closed_extended_warranty_billing_line_id',
      v_current_line.id,
    'post_coverage_billing_line_id',
      v_split_line_id,
    'post_coverage_pay_type_rule_id',
      v_post_coverage_pay_type.id,
    'post_coverage_pay_type',
      v_post_coverage_pay_type.pay_type
  );
END;
$function$

CREATE OR REPLACE FUNCTION public.reconcile_extended_warranty_coverage_and_get_state(p_transportation_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_user_id uuid;
  v_checked_at timestamptz;
  v_reconciliation_result jsonb;
  v_case public.warranty_cases%ROWTYPE;
  v_current_vehicle_event public.vehicle_events%ROWTYPE;
  v_post_coverage_pay_type public.pay_type_rules%ROWTYPE;
  v_effective_covered_days integer;
  v_coverage_boundary timestamptz;
  v_current_vehicle_contract_day integer;
  v_billing_lines jsonb;
  v_can_override boolean;
BEGIN
  IF p_transportation_event_id IS NULL THEN
    RAISE EXCEPTION 'Transportation event is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT au.id
    INTO v_actor_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'An active application user is required'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
    RAISE EXCEPTION 'AAL2 authentication is required'
      USING ERRCODE = '42501';
  END IF;

  v_checked_at := clock_timestamp();

  v_reconciliation_result :=
    public.reconcile_extended_warranty_coverage_state(
      p_transportation_event_id,
      v_checked_at
    );

  SELECT warranty_case.*
    INTO v_case
  FROM public.warranty_cases warranty_case
  WHERE warranty_case.transportation_event_id =
    p_transportation_event_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'extended_warranty_case_not_configured',
      'transportation_event_id',
        p_transportation_event_id,
      'checked_at', v_checked_at,
      'reconciliation_result',
        v_reconciliation_result
    );
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.v_user_effective_permissions permission
    WHERE permission.user_id = v_actor_user_id
      AND permission.permission_key =
        'billing.extended_warranty_override'
  )
    INTO v_can_override;

  SELECT rule.*
    INTO v_post_coverage_pay_type
  FROM public.pay_type_rules rule
  WHERE rule.id =
    v_case.post_coverage_pay_type_rule_id;

  IF (
    SELECT count(*)
    FROM public.vehicle_events vehicle_event
    WHERE vehicle_event.transportation_event_id =
        p_transportation_event_id
      AND vehicle_event.is_open = true
  ) > 1 THEN
    RAISE EXCEPTION 'Transportation event has multiple open vehicle assignments'
      USING ERRCODE = '21000';
  END IF;

  SELECT vehicle_event.*
    INTO v_current_vehicle_event
  FROM public.vehicle_events vehicle_event
  WHERE vehicle_event.transportation_event_id =
      p_transportation_event_id
    AND vehicle_event.is_open = true
  ORDER BY vehicle_event.actual_out_at DESC,
           vehicle_event.id DESC
  LIMIT 1;

  IF FOUND THEN
    v_current_vehicle_contract_day :=
      public.business_contract_days(
        v_current_vehicle_event.actual_out_at,
        v_checked_at
      );
  ELSE
    v_current_vehicle_contract_day := NULL;
  END IF;

  v_effective_covered_days :=
    coalesce(
      v_case.approved_days,
      v_case.default_covered_days_snapshot
    );

  IF v_effective_covered_days IS NOT NULL THEN
    v_coverage_boundary :=
      v_case.coverage_started_at
      + make_interval(days => v_effective_covered_days);
  ELSE
    v_coverage_boundary := NULL;
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'billing_line_id', line.id,
        'parent_billing_line_id',
          line.parent_billing_line_id,
        'extended_from_billing_line_id',
          line.extended_from_billing_line_id,
        'vehicle_id', line.vehicle_id,
        'vehicle_event_id', line.vehicle_event_id,
        'contract_period_id', line.contract_period_id,
        'pay_type_rule_id', line.pay_type_rule_id,
        'pay_type', line.pay_type,
        'line_type', line.line_type,
        'source_rule', line.source_rule,
        'amount', line.amount,
        'tax_amount', line.tax_amount,
        'start_time', line.start_time,
        'end_time', line.end_time,
        'paid_through_at', line.paid_through_at,
        'is_open', line.is_open,
        'warranty_provider_id',
          line.warranty_provider_id,
        'default_covered_days_snapshot',
          line.default_covered_days_snapshot,
        'covered_days_override',
          line.covered_days_override,
        'default_daily_rate_snapshot',
          line.default_daily_rate_snapshot,
        'daily_rate_override',
          line.daily_rate_override,
        'created_at', line.created_at,
        'updated_at', line.updated_at
      )
      ORDER BY line.start_time,
               line.created_at,
               line.id
    ),
    '[]'::jsonb
  )
    INTO v_billing_lines
  FROM public.billing_lines line
  WHERE line.transportation_event_id =
    p_transportation_event_id;

  RETURN jsonb_build_object(
    'status',
      'extended_warranty_coverage_reconciled_and_loaded',
    'checked_at', v_checked_at,
    'can_override', v_can_override,
    'reconciliation_result',
      v_reconciliation_result,
    'extended_warranty_case',
      jsonb_build_object(
        'case_id', v_case.id,
        'transportation_event_id',
          v_case.transportation_event_id,
        'reservation_id', v_case.reservation_id,
        'provider_id', v_case.provider_id,
        'provider_name', v_case.provider_name,
        'extended_warranty_rule_id',
          v_case.extended_warranty_rule_id,
        'default_covered_days_snapshot',
          v_case.default_covered_days_snapshot,
        'approved_days', v_case.approved_days,
        'effective_covered_days',
          v_effective_covered_days,
        'default_daily_rate_snapshot',
          v_case.default_daily_rate_snapshot,
        'coverage_started_at',
          v_case.coverage_started_at,
        'coverage_boundary',
          v_coverage_boundary,
        'coverage_exhausted_at',
          v_case.coverage_exhausted_at,
        'current_contract_day',
          v_case.current_day_count,
        'approval_status',
          v_case.approval_status,
        'requires_manual_review',
          v_case.requires_manual_review,
        'escalation_level',
          v_case.escalation_level,
        'post_coverage_pay_type_rule_id',
          v_case.post_coverage_pay_type_rule_id,
        'post_coverage_pay_type',
          v_post_coverage_pay_type.pay_type,
        'override_reason',
          v_case.override_reason,
        'override_authorized_by',
          v_case.override_authorized_by,
        'override_authorized_at',
          v_case.override_authorized_at,
        'created_at', v_case.created_at,
        'updated_at', v_case.updated_at
      ),
    'current_vehicle',
      CASE
        WHEN v_current_vehicle_event.id IS NULL
          THEN NULL
        ELSE jsonb_build_object(
          'vehicle_event_id',
            v_current_vehicle_event.id,
          'vehicle_id',
            v_current_vehicle_event.vehicle_id,
          'actual_out_at',
            v_current_vehicle_event.actual_out_at,
          'actual_in_at',
            v_current_vehicle_event.actual_in_at,
          'is_open',
            v_current_vehicle_event.is_open,
          'current_vehicle_contract_day',
            v_current_vehicle_contract_day
        )
      END,
    'billing_lines', v_billing_lines
  );
END;
$function$

alter function public.get_admin_billing_configuration_state() owner to postgres;
alter function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) owner to postgres;
alter function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) owner to postgres;
alter function public.set_admin_extended_warranty_provider_enabled_state(uuid,boolean) owner to postgres;
alter function public.create_extended_warranty_case_and_get_state(uuid,uuid) owner to postgres;
alter function public.set_extended_warranty_case_override_and_get_state(uuid,integer,uuid,text) owner to postgres;
alter function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) owner to postgres;
alter function public.reconcile_extended_warranty_coverage_and_get_state(uuid) owner to postgres;

revoke all on function public.create_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) from public, anon, authenticated;
revoke all on function public.update_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) from public, anon, authenticated;
revoke all on function public.set_extended_warranty_rule_active_state(uuid,boolean) from public, anon, authenticated;
revoke all on function public.resolve_extended_warranty_provider_default_state(uuid) from public, anon, authenticated;
grant execute on function public.create_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) to service_role;
grant execute on function public.update_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) to service_role;
grant execute on function public.set_extended_warranty_rule_active_state(uuid,boolean) to service_role;
grant execute on function public.resolve_extended_warranty_provider_default_state(uuid) to service_role;

revoke all on function public.get_admin_billing_configuration_state() from public, anon, authenticated;
revoke all on function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) from public, anon, authenticated;
revoke all on function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) from public, anon, authenticated;
revoke all on function public.set_admin_extended_warranty_provider_enabled_state(uuid,boolean) from public, anon, authenticated;
revoke all on function public.create_extended_warranty_case_and_get_state(uuid,uuid) from public, anon, authenticated;
revoke all on function public.set_extended_warranty_case_override_and_get_state(uuid,integer,uuid,text) from public, anon, authenticated;
revoke all on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) from public, anon, authenticated;
revoke all on function public.reconcile_extended_warranty_coverage_and_get_state(uuid) from public, anon, authenticated;

grant execute on function public.get_admin_billing_configuration_state() to authenticated, service_role;
grant execute on function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) to authenticated, service_role;
grant execute on function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) to authenticated, service_role;
grant execute on function public.set_admin_extended_warranty_provider_enabled_state(uuid,boolean) to authenticated, service_role;
grant execute on function public.create_extended_warranty_case_and_get_state(uuid,uuid) to authenticated, service_role;
grant execute on function public.set_extended_warranty_case_override_and_get_state(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function public.reconcile_extended_warranty_coverage_and_get_state(uuid) to authenticated, service_role;
grant execute on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) to service_role;
