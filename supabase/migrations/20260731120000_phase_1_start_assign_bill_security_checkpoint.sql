-- Phase 1 start/assign/bill browser boundary security checkpoint.
-- This migration is repository-only and must not be applied to production by this task.

do $precondition$
begin
  if exists (
    select 1
    from public.vehicle_events
    where is_open = true
    group by vehicle_id
    having count(*) > 1
  ) then
    raise exception using
      errcode = '23505',
      message = 'Cannot enforce one open vehicle event per vehicle: conflicting open vehicle_events rows exist';
  end if;
end
$precondition$;

create unique index if not exists ux_vehicle_events_one_open_per_vehicle
  on public.vehicle_events (vehicle_id)
  where is_open = true;

create or replace function public.create_start_bill_case_and_get_payload_state(
  p_tekion_customer_number text,
  p_customer_name text,
  p_start_date timestamptz,
  p_expected_return_datetime timestamptz,
  p_requested_model text,
  p_vehicle_vin text,
  p_vehicle_stock_number text,
  p_vehicle_model text,
  p_vehicle_fleet_type text,
  p_vehicle_mileage integer,
  p_vehicle_current_tag text,
  p_vehicle_fleet_conversion_type text,
  p_actual_out_at timestamptz,
  p_billing_amount numeric,
  p_billing_tax_amount numeric default 0,
  p_billing_start_time timestamptz default null,
  p_billing_paid_through_at timestamptz default null,
  p_customer_phone text default null,
  p_customer_email text default null,
  p_customer_flags jsonb default null,
  p_customer_internal_notes text default null,
  p_reservation_type text default 'rental',
  p_reservation_status text default 'quote',
  p_reservation_notes text default null,
  p_service_advisor text default null,
  p_ro_number text default null,
  p_pay_type text default 'customer',
  p_vehicle_location text default null,
  p_vehicle_notes text default null,
  p_vehicle_status text default 'available',
  p_vehicle_recon_status text default 'clean',
  p_billing_line_type text default 'initial_assignment',
  p_billing_source_rule text default null,
  p_start_mileage integer default null,
  p_entered_by_user_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_user_id uuid;
  v_execution_result jsonb;
  v_reservation_id uuid;
  v_vehicle_event_id uuid;
  v_contract_period_id uuid;
  v_unified_payload jsonb;
begin
  select au.id
    into v_actor_user_id
  from public.app_users as au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'An active application user is required';
  end if;

  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2 authentication is required';
  end if;

  if p_entered_by_user_id is not null and p_entered_by_user_id <> v_actor_user_id then
    raise exception using errcode = '42501', message = 'entered_by_user_id must match the authenticated application user';
  end if;

  if p_start_mileage is not null and p_start_mileage < 0 then
    raise exception 'start_mileage must be non-negative';
  end if;

  v_execution_result := public.create_start_and_bill_case_with_vehicle_by_vin_state(
    p_tekion_customer_number, p_customer_name, p_start_date,
    p_expected_return_datetime, p_requested_model, p_vehicle_vin,
    p_vehicle_stock_number, p_vehicle_model, p_vehicle_fleet_type,
    p_vehicle_mileage, p_vehicle_current_tag, p_vehicle_fleet_conversion_type,
    p_actual_out_at, p_billing_amount, coalesce(p_billing_tax_amount, 0),
    p_billing_start_time, p_billing_paid_through_at, p_customer_phone,
    p_customer_email, p_customer_flags, p_customer_internal_notes,
    p_reservation_type, p_reservation_status, p_reservation_notes,
    p_service_advisor, p_ro_number, p_pay_type, p_vehicle_location,
    p_vehicle_notes, p_vehicle_status, p_vehicle_recon_status,
    p_billing_line_type, p_billing_source_rule
  );

  begin
    v_reservation_id := (v_execution_result ->> 'reservation_id')::uuid;
    v_vehicle_event_id := (v_execution_result -> 'case_step' -> 'start_result' -> 'continuity_result' ->> 'vehicle_event_id')::uuid;
    v_contract_period_id := (v_execution_result -> 'case_step' -> 'start_result' -> 'continuity_result' ->> 'contract_period_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Workflow returned malformed created identifiers';
  end;

  if v_reservation_id is null or v_vehicle_event_id is null or v_contract_period_id is null then
    raise exception 'Workflow did not return reservation, vehicle-event, and contract-period identifiers';
  end if;

  if not exists (
    select 1
    from public.reservations r
    join public.vehicle_events ve on ve.transportation_event_id = r.transportation_event_id
    join public.contract_periods cp on cp.vehicle_event_id = ve.id
    where r.id = v_reservation_id
      and ve.id = v_vehicle_event_id
      and cp.id = v_contract_period_id
  ) then
    raise exception 'Workflow returned identifiers that do not identify the created case continuity rows';
  end if;

  if p_start_mileage is not null then
    update public.reservations
    set start_mileage = p_start_mileage
    where id = v_reservation_id;
  end if;

  update public.vehicle_events
  set created_by = v_actor_user_id,
      updated_by = v_actor_user_id
  where id = v_vehicle_event_id;

  update public.contract_periods
  set created_by = v_actor_user_id,
      updated_by = v_actor_user_id
  where id = v_contract_period_id;

  v_unified_payload := public.get_unified_case_payload_state(v_reservation_id);

  return jsonb_build_object(
    'status', 'full_case_created_started_billed_and_loaded',
    'reservation_id', v_reservation_id,
    'execution_result', v_execution_result,
    'unified_case_payload', v_unified_payload
  );
end
$function$;

alter function public.create_start_bill_case_and_get_payload_state(
  text, text, timestamptz, timestamptz, text, text, text, text, text,
  integer, text, text, timestamptz, numeric, numeric, timestamptz,
  timestamptz, text, text, jsonb, text, text, text, text, text, text,
  text, text, text, text, text, text, integer, uuid
) owner to postgres;

revoke all on function public.create_start_bill_case_and_get_payload_state(
  text, text, timestamptz, timestamptz, text, text, text, text, text,
  integer, text, text, timestamptz, numeric, numeric, timestamptz,
  timestamptz, text, text, jsonb, text, text, text, text, text, text,
  text, text, text, text, text, text, integer, uuid
) from public, anon, service_role;
grant execute on function public.create_start_bill_case_and_get_payload_state(
  text, text, timestamptz, timestamptz, text, text, text, text, text,
  integer, text, text, timestamptz, numeric, numeric, timestamptz,
  timestamptz, text, text, jsonb, text, text, text, text, text, text,
  text, text, text, text, text, text, integer, uuid
) to authenticated;

insert into public.service_action_contracts (
  action_key, action_group, entity_scope, db_function_name, action_type,
  description, requires_authenticated_user, requires_aal2, writes_data,
  frontend_safe, internal_only, required_permission
) values (
  'case.create_start_bill_and_load', 'case', 'reservation_case',
  'create_start_bill_case_and_get_payload_state', 'write',
  'Create, start, bill, and immediately load a unified case payload.',
  true, true, true, true, false, null
)
on conflict (action_key) do update set
  action_group = excluded.action_group,
  entity_scope = excluded.entity_scope,
  db_function_name = excluded.db_function_name,
  action_type = excluded.action_type,
  description = excluded.description,
  requires_authenticated_user = excluded.requires_authenticated_user,
  requires_aal2 = excluded.requires_aal2,
  writes_data = excluded.writes_data,
  frontend_safe = excluded.frontend_safe,
  internal_only = excluded.internal_only,
  required_permission = excluded.required_permission,
  updated_at = now();

-- The read helper get_unified_case_payload_state intentionally remains unchanged.
-- Restrict the legacy wrapper and the complete mutating helper chain below it.
do $grants$
declare
  v_function record;
begin
  for v_function in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        'create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_',
        'create_start_and_bill_case_with_vehicle_by_vin_state',
        'create_and_start_case_with_vehicle_by_vin_state',
        'create_case_bootstrap_with_vehicle_by_vin_state',
        'create_case_bootstrap_state',
        'get_or_create_customer_state_by_tekion',
        'create_customer_state',
        'get_or_create_vehicle_state_by_vin',
        'create_vehicle_state',
        'create_reservation_for_tekion_customer_state',
        'create_reservation_with_transportation_event_state',
        'start_reservation_vehicle_use_state',
        'start_vehicle_use_state',
        'activate_case_billing_state',
        'create_reservation_billing_line_state',
        'create_billing_parent_line_state',
        'ensure_tax_child_line_state'
      ])
  loop
    execute format('revoke execute on function %I.%I(%s) from public, anon, authenticated',
      v_function.nspname, v_function.proname, v_function.args);
    execute format('grant execute on function %I.%I(%s) to service_role',
      v_function.nspname, v_function.proname, v_function.args);
  end loop;
end
$grants$;

revoke insert, update, delete on table
  public.customers,
  public.vehicles,
  public.transportation_events,
  public.reservations,
  public.vehicle_events,
  public.contract_periods,
  public.billing_lines
from public, anon, authenticated;

grant insert, update, delete on table
  public.customers,
  public.vehicles,
  public.transportation_events,
  public.reservations,
  public.vehicle_events,
  public.contract_periods,
  public.billing_lines
to service_role;
