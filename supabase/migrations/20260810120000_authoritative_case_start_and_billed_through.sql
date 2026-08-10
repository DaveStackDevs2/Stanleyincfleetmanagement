-- Record the verified live authoritative case-start and Tekion checkpoint contracts.
-- This migration is deliberately data-free and safe to re-run.

insert into public.permissions (permission_key, description)
values
  ('billing.case_start', 'Can create and start a transportation case with authoritative initial billing'),
  ('billing.mark_billed_through', 'Can record the date and time through which transportation charges have been transferred to the dealership billing system')
on conflict (permission_key) do update set description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.role_name = 'Dev'
  and p.permission_key in ('billing.case_start', 'billing.mark_billed_through')
on conflict do nothing;

create or replace function public.create_authoritative_start_bill_case_state(
  p_customer_id uuid, p_vehicle_id uuid, p_start_date timestamptz,
  p_expected_return_datetime timestamptz, p_actual_out_at timestamptz,
  p_reservation_type text, p_ro_number text, p_pay_type text,
  p_reservation_notes text default null, p_service_advisor text default null,
  p_start_mileage integer default null
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_actor uuid; v_customer public.customers%rowtype; v_vehicle public.vehicles%rowtype;
  v_create jsonb; v_preview jsonb; v_line jsonb; v_preview_at timestamptz;
  v_reservation uuid; v_event uuid; v_vehicle_event uuid; v_period uuid;
  v_line_id uuid; v_final jsonb;
begin
  select au.id into v_actor from public.app_users au
  where au.auth_user_id = auth.uid() and au.is_active = true;
  if v_actor is null then raise exception using errcode='42501', message='An active application user is required'; end if;
  if not exists (select 1 from public.v_user_effective_permissions ep where ep.user_id=v_actor and ep.permission_key='billing.case_start') then
    raise exception using errcode='42501', message='Permission denied';
  end if;
  if p_customer_id is null or p_vehicle_id is null or p_start_date is null or p_expected_return_datetime is null or p_actual_out_at is null then
    raise exception using errcode='22023', message='Customer, vehicle, and case dates are required';
  end if;
  if p_expected_return_datetime <= p_start_date then raise exception using errcode='22023', message='Expected return must be after case start'; end if;
  if p_actual_out_at < p_start_date then raise exception using errcode='22023', message='Actual out timestamp cannot precede case start'; end if;
  if p_reservation_type is null or btrim(p_reservation_type) = '' then raise exception using errcode='22023', message='Reservation type is required'; end if;
  if p_pay_type is null or btrim(p_pay_type) = '' then raise exception using errcode='22023', message='Pay type is required'; end if;
  if p_start_mileage is not null and p_start_mileage < 0 then raise exception using errcode='22023', message='Start mileage must be non-negative'; end if;

  select * into v_customer from public.customers where id=p_customer_id for share;
  if not found then raise exception using errcode='P0002', message='Customer was not found'; end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and is_retired = false for update;
  if not found then raise exception using errcode='P0002', message='Vehicle is unavailable'; end if;

  v_create := public.create_and_start_case_with_vehicle_by_vin_state(
    v_customer.tekion_customer_number, v_customer.name, p_start_date,
    p_expected_return_datetime, v_vehicle.model, v_vehicle.vin,
    v_vehicle.stock_number, v_vehicle.model, v_vehicle.fleet_type,
    v_vehicle.mileage, v_vehicle.current_tag, v_vehicle.fleet_conversion_type,
    p_actual_out_at, v_customer.phone, v_customer.email, v_customer.flags,
    v_customer.internal_notes, btrim(p_reservation_type), 'active',
    nullif(btrim(p_reservation_notes), ''), nullif(btrim(p_service_advisor), ''),
    nullif(btrim(p_ro_number), ''), btrim(p_pay_type),
    v_vehicle.location, v_vehicle.notes, v_vehicle.status, v_vehicle.recon_status);
  begin
    v_reservation := (v_create->>'reservation_id')::uuid;
    v_event := (v_create->>'transportation_event_id')::uuid;
    v_vehicle_event := (v_create->'start_result'->'continuity_result'->>'vehicle_event_id')::uuid;
    v_period := (v_create->'start_result'->'continuity_result'->>'contract_period_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Workflow returned malformed created identifiers';
  end;
  if v_reservation is null or v_event is null or v_vehicle_event is null or v_period is null then raise exception 'Workflow did not return complete created identifiers'; end if;
  if not exists (select 1 from public.reservations r join public.vehicle_events ve on ve.transportation_event_id=r.transportation_event_id join public.contract_periods cp on cp.vehicle_event_id=ve.id where r.id=v_reservation and r.transportation_event_id=v_event and ve.id=v_vehicle_event and ve.vehicle_id=p_vehicle_id and cp.id=v_period) then
    raise exception 'Workflow returned identifiers that do not identify the created case continuity rows';
  end if;
  if p_start_mileage is not null then update public.reservations set start_mileage=p_start_mileage where id=v_reservation; end if;
  update public.vehicle_events set created_by=v_actor, updated_by=v_actor where id=v_vehicle_event;
  update public.contract_periods set created_by=v_actor, updated_by=v_actor where id=v_period;

  v_preview_at := clock_timestamp();
  v_preview := public.get_billing_preview_state(v_event, v_preview_at);
  if v_preview->>'status' <> 'billing_preview_ready' then raise exception 'Authoritative billing preview is not ready'; end if;
  v_line := public.create_billing_parent_line_state(
    v_event, v_reservation, p_vehicle_id, v_preview->>'pay_type',
    (v_preview->>'subtotal')::numeric, (v_preview->>'tax_amount')::numeric,
    (v_preview->>'billing_start')::timestamptz, null, v_preview->>'rate_source', v_vehicle_event, v_period,
    'initial_assignment', null, null, null, true, null, null,
    (v_preview->>'daily_rate')::numeric, null);
  if v_line->>'status' <> 'parent_billing_line_created' then raise exception 'Authoritative parent billing line was not created'; end if;
  begin v_line_id := (v_line->>'parent_billing_line_id')::uuid;
  exception when invalid_text_representation then raise exception 'Billing engine returned a malformed parent billing line identifier'; end;
  if v_line_id is null then raise exception 'Billing engine returned no parent billing line'; end if;
  v_final := public.get_billing_preview_state(v_event, clock_timestamp());
  if v_final->>'status' <> 'billing_preview_ready' then raise exception 'Current authoritative billing preview is not ready'; end if;
  return jsonb_build_object('status','authoritative_case_created_started_billed',
    'reservation_id',v_reservation,'transportation_event_id',v_event,
    'vehicle_event_id',v_vehicle_event,'contract_period_id',v_period,
    'billing_line_id',v_line_id,'billing_preview',v_final);
end;
$function$;

alter function public.create_authoritative_start_bill_case_state(uuid,uuid,timestamptz,timestamptz,timestamptz,text,text,text,text,text,integer) owner to postgres;
revoke all on function public.create_authoritative_start_bill_case_state(uuid,uuid,timestamptz,timestamptz,timestamptz,text,text,text,text,text,integer) from public, anon, authenticated, service_role;
grant execute on function public.create_authoritative_start_bill_case_state(uuid,uuid,timestamptz,timestamptz,timestamptz,text,text,text,text,text,integer) to authenticated, service_role;

create or replace function public.mark_case_billed_through_and_get_preview_state(
  p_reservation_id uuid, p_billed_through_at timestamptz, p_note text
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_actor uuid; v_res public.reservations%rowtype; v_line public.billing_lines%rowtype;
  v_preview jsonb; v_tax jsonb; v_current jsonb; v_open_count integer;
  v_now timestamptz; v_set_result jsonb; v_tax_update_count integer;
begin
  select au.id into v_actor from public.app_users au
  where au.auth_user_id=auth.uid() and au.is_active=true;
  if v_actor is null then raise exception using errcode='42501', message='An active application user is required'; end if;
  if not exists (select 1 from public.v_user_effective_permissions ep where ep.user_id=v_actor and ep.permission_key='billing.mark_billed_through') then
    raise exception using errcode='42501', message='Permission denied';
  end if;
  if p_reservation_id is null or p_billed_through_at is null then raise exception using errcode='22023', message='Reservation and billed-through timestamp are required'; end if;
  v_now := clock_timestamp();
  if p_billed_through_at > v_now then raise exception using errcode='22023', message='Billed-through timestamp cannot be in the future'; end if;
  select * into v_res from public.reservations where id=p_reservation_id for update;
  if not found then raise exception using errcode='P0002', message='Reservation was not found'; end if;
  if p_billed_through_at < v_res.start_date then raise exception using errcode='22023', message='Billed-through timestamp cannot precede case start'; end if;
  if v_res.billed_through_datetime is not null and p_billed_through_at < v_res.billed_through_datetime then raise exception using errcode='22023', message='Billed-through timestamp cannot move backward'; end if;
  select count(*) into v_open_count from public.billing_lines bl where bl.reservation_id=p_reservation_id and bl.transportation_event_id=v_res.transportation_event_id and bl.parent_billing_line_id is null and bl.is_open=true;
  if v_open_count = 0 then raise exception using errcode='P0002', message='Open parent billing segment was not found'; end if;
  if v_open_count > 1 then raise exception using errcode='21000', message='Multiple open parent billing segments were found'; end if;
  select * into v_line from public.billing_lines bl where bl.reservation_id=p_reservation_id and bl.transportation_event_id=v_res.transportation_event_id and bl.parent_billing_line_id is null and bl.is_open=true for update;
  v_preview := public.get_billing_preview_state(v_res.transportation_event_id,p_billed_through_at);
  if v_preview->>'status' <> 'billing_preview_ready' then raise exception 'Authoritative checkpoint preview is not ready'; end if;
  v_set_result := public.set_reservation_billed_through_state(p_reservation_id,p_billed_through_at,nullif(btrim(p_note),''));
  if v_set_result->>'status' <> 'reservation_billed_through_set' then raise exception 'Reservation billed-through timestamp was not set'; end if;
  update public.billing_lines set amount=(v_preview->>'subtotal')::numeric,
    tax_amount=(v_preview->>'tax_amount')::numeric, paid_through_at=p_billed_through_at,
    updated_at=clock_timestamp()
    where id=v_line.id;
  v_tax := public.ensure_tax_child_line_state(v_line.id);
  update public.billing_lines set paid_through_at=p_billed_through_at, updated_at=clock_timestamp()
    where parent_billing_line_id=v_line.id and line_type='tax';
  get diagnostics v_tax_update_count = row_count;
  if (v_preview->>'tax_amount')::numeric > 0 and v_tax_update_count <> 1 then raise exception 'Positive checkpoint tax requires exactly one synchronized tax child'; end if;
  v_current := public.get_billing_preview_state(v_res.transportation_event_id,clock_timestamp());
  if v_current->>'status' <> 'billing_preview_ready' then raise exception 'Current authoritative billing preview is not ready'; end if;
  return jsonb_build_object('status','billing_checkpoint_recorded','reservation_id',p_reservation_id,
    'transportation_event_id',v_res.transportation_event_id,'billing_line_id',v_line.id,
    'billed_through_at',p_billed_through_at,'checkpoint_subtotal',v_preview->>'subtotal',
    'checkpoint_tax',v_preview->>'tax_amount','checkpoint_total',v_preview->>'total',
    'tax_child_result',v_tax,'billing_preview',v_current);
end;
$function$;

alter function public.mark_case_billed_through_and_get_preview_state(uuid,timestamptz,text) owner to postgres;
revoke all on function public.mark_case_billed_through_and_get_preview_state(uuid,timestamptz,text) from public, anon, authenticated, service_role;
grant execute on function public.mark_case_billed_through_and_get_preview_state(uuid,timestamptz,text) to authenticated, service_role;

-- The legacy amount-taking wrapper remains available only to its owner.
revoke execute on function public.create_start_bill_case_and_get_payload_state(text,text,timestamptz,timestamptz,text,text,text,text,text,integer,text,text,timestamptz,numeric,numeric,timestamptz,timestamptz,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text,integer,uuid) from authenticated;
revoke all on function public.set_reservation_billed_through_state(uuid,timestamptz,text) from public, anon, authenticated;
grant execute on function public.set_reservation_billed_through_state(uuid,timestamptz,text) to postgres, service_role;
