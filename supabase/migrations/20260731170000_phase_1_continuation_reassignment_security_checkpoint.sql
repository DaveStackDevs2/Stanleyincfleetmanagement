-- Phase 1 continuation/reassignment browser-boundary security checkpoint.
-- Repository only: this migration must be manually reviewed before live application.

create or replace function public.restart_same_vehicle_after_gap(
  p_transportation_event_id uuid,
  p_vehicle_id uuid,
  p_new_actual_out_at timestamptz
) returns jsonb
language plpgsql
security invoker
set search_path to ''
as $function$
begin
  return public.start_vehicle_use_state(
    p_transportation_event_id,
    p_vehicle_id,
    p_new_actual_out_at
  );
end;
$function$;

alter function public.restart_same_vehicle_after_gap(uuid, uuid, timestamptz) owner to postgres;
revoke all on function public.restart_same_vehicle_after_gap(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.restart_same_vehicle_after_gap(uuid, uuid, timestamptz) to service_role;

create or replace function public.continue_case_same_vehicle_and_get_unified_payload_state(
  p_reservation_id uuid,
  p_new_time timestamptz
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_user_id uuid;
  v_action_result jsonb;
  v_action_status text;
  v_transportation_event_id uuid;
  v_vehicle_id uuid;
  v_vehicle_event_id uuid;
  v_old_contract_period_id uuid;
  v_new_contract_period_id uuid;
  v_unified_payload jsonb;
begin
  select au.id into v_actor_user_id
  from public.app_users as au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'An active application user is required';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2 authentication is required';
  end if;

  v_action_result := public.continue_case_same_vehicle_state(p_reservation_id, p_new_time);
  v_action_status := v_action_result ->> 'status';

  begin
    v_transportation_event_id := (v_action_result ->> 'transportation_event_id')::uuid;
    v_vehicle_id := (v_action_result ->> 'vehicle_id')::uuid;
    if v_action_status = 'case_continued_via_same_vehicle_renewal' then
      v_vehicle_event_id := (v_action_result -> 'continuation_result' ->> 'vehicle_event_id')::uuid;
      v_old_contract_period_id := (v_action_result -> 'continuation_result' -> 'continuity_renew_result' ->> 'old_contract_period_id')::uuid;
      v_new_contract_period_id := (v_action_result -> 'continuation_result' -> 'continuity_renew_result' ->> 'new_contract_period_id')::uuid;
    elsif v_action_status = 'case_continued_via_same_vehicle_restart_after_gap' then
      v_vehicle_event_id := (v_action_result -> 'continuation_result' -> 'continuity_restart_result' ->> 'vehicle_event_id')::uuid;
      v_new_contract_period_id := (v_action_result -> 'continuation_result' -> 'continuity_restart_result' ->> 'contract_period_id')::uuid;
    else
      raise exception 'Continuation workflow returned an unexpected status';
    end if;
  exception when invalid_text_representation then
    raise exception 'Continuation workflow returned malformed identifiers';
  end;

  if v_transportation_event_id is null or v_vehicle_id is null
     or v_vehicle_event_id is null or v_new_contract_period_id is null
     or (v_action_status = 'case_continued_via_same_vehicle_renewal' and v_old_contract_period_id is null) then
    raise exception 'Continuation workflow did not return all required identifiers';
  end if;

  if not exists (
    select 1 from public.reservations r
    join public.vehicle_events ve on ve.transportation_event_id = r.transportation_event_id
    join public.contract_periods new_cp on new_cp.vehicle_event_id = ve.id
    where r.id = p_reservation_id
      and r.transportation_event_id = v_transportation_event_id
      and ve.id = v_vehicle_event_id and ve.vehicle_id = v_vehicle_id
      and new_cp.id = v_new_contract_period_id
  ) then
    raise exception 'Continuation workflow returned identifiers outside the affected case';
  end if;

  if v_action_status = 'case_continued_via_same_vehicle_renewal' then
    if not exists (
      select 1 from public.contract_periods
      where id = v_old_contract_period_id and vehicle_event_id = v_vehicle_event_id and is_open = false
    ) then
      raise exception 'Continuation workflow did not identify the exact closed contract period';
    end if;
    update public.contract_periods set updated_by = v_actor_user_id
    where id = v_old_contract_period_id and vehicle_event_id = v_vehicle_event_id;
  else
    update public.vehicle_events
    set created_by = v_actor_user_id, updated_by = v_actor_user_id
    where id = v_vehicle_event_id
      and transportation_event_id = v_transportation_event_id and vehicle_id = v_vehicle_id;
  end if;

  update public.contract_periods
  set created_by = v_actor_user_id, updated_by = v_actor_user_id
  where id = v_new_contract_period_id and vehicle_event_id = v_vehicle_event_id;

  v_unified_payload := public.get_unified_case_payload_state(p_reservation_id);
  return jsonb_build_object(
    'status', 'case_continued_and_loaded', 'reservation_id', p_reservation_id,
    'action_result', v_action_result, 'unified_case_payload', v_unified_payload
  );
end;
$function$;

alter function public.continue_case_same_vehicle_and_get_unified_payload_state(uuid, timestamptz) owner to postgres;
revoke all on function public.continue_case_same_vehicle_and_get_unified_payload_state(uuid, timestamptz) from public, anon, service_role;
grant execute on function public.continue_case_same_vehicle_and_get_unified_payload_state(uuid, timestamptz) to authenticated;

create or replace function public.reassign_active_case_to_vehicle_and_get_unified_payload_state(
  p_reservation_id uuid,
  p_new_vehicle_id uuid,
  p_swap_time timestamptz,
  p_actor_user_id uuid default null,
  p_resolve_current_dependency boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_user_id uuid;
  v_action_result jsonb;
  v_transportation_event_id uuid;
  v_old_vehicle_event_id uuid;
  v_old_contract_period_id uuid;
  v_new_vehicle_event_id uuid;
  v_new_contract_period_id uuid;
  v_unified_payload jsonb;
begin
  select au.id into v_actor_user_id
  from public.app_users as au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'An active application user is required';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2 authentication is required';
  end if;
  if p_actor_user_id is not null and p_actor_user_id <> v_actor_user_id then
    raise exception using errcode = '42501', message = 'actor_user_id must match the authenticated application user';
  end if;

  v_action_result := public.reassign_active_case_to_vehicle_state(
    p_reservation_id, p_new_vehicle_id, p_swap_time,
    v_actor_user_id, p_resolve_current_dependency
  );

  begin
    v_transportation_event_id := (v_action_result ->> 'transportation_event_id')::uuid;
    v_old_vehicle_event_id := (v_action_result ->> 'old_vehicle_event_id')::uuid;
    v_old_contract_period_id := (v_action_result -> 'swap_result' -> 'continuity_swap_result' ->> 'old_contract_period_id')::uuid;
    v_new_vehicle_event_id := (v_action_result -> 'swap_result' -> 'continuity_swap_result' ->> 'new_vehicle_event_id')::uuid;
    v_new_contract_period_id := (v_action_result -> 'swap_result' -> 'continuity_swap_result' ->> 'new_contract_period_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Reassignment workflow returned malformed identifiers';
  end;

  if v_transportation_event_id is null or v_old_vehicle_event_id is null
     or v_old_contract_period_id is null or v_new_vehicle_event_id is null
     or v_new_contract_period_id is null then
    raise exception 'Reassignment workflow did not return all required identifiers';
  end if;

  if not exists (
    select 1 from public.reservations r
    join public.vehicle_events old_ve on old_ve.transportation_event_id = r.transportation_event_id
    join public.contract_periods old_cp on old_cp.vehicle_event_id = old_ve.id
    join public.vehicle_events new_ve on new_ve.transportation_event_id = r.transportation_event_id
    join public.contract_periods new_cp on new_cp.vehicle_event_id = new_ve.id
    where r.id = p_reservation_id and r.transportation_event_id = v_transportation_event_id
      and old_ve.id = v_old_vehicle_event_id and old_ve.is_open = false
      and old_cp.id = v_old_contract_period_id and old_cp.is_open = false
      and new_ve.id = v_new_vehicle_event_id and new_ve.vehicle_id = p_new_vehicle_id
      and new_cp.id = v_new_contract_period_id
  ) then
    raise exception 'Reassignment workflow returned identifiers outside the affected case and exact new vehicle';
  end if;

  update public.vehicle_events set updated_by = v_actor_user_id
  where id = v_old_vehicle_event_id and transportation_event_id = v_transportation_event_id;
  update public.contract_periods set updated_by = v_actor_user_id
  where id = v_old_contract_period_id and vehicle_event_id = v_old_vehicle_event_id;
  update public.vehicle_events set created_by = v_actor_user_id, updated_by = v_actor_user_id
  where id = v_new_vehicle_event_id
    and transportation_event_id = v_transportation_event_id and vehicle_id = p_new_vehicle_id;
  update public.contract_periods set created_by = v_actor_user_id, updated_by = v_actor_user_id
  where id = v_new_contract_period_id and vehicle_event_id = v_new_vehicle_event_id;

  v_unified_payload := public.get_unified_case_payload_state(p_reservation_id);
  return jsonb_build_object(
    'status', 'case_reassigned_and_loaded', 'reservation_id', p_reservation_id,
    'action_result', v_action_result, 'unified_case_payload', v_unified_payload
  );
end;
$function$;

alter function public.reassign_active_case_to_vehicle_and_get_unified_payload_state(uuid, uuid, timestamptz, uuid, boolean) owner to postgres;
revoke all on function public.reassign_active_case_to_vehicle_and_get_unified_payload_state(uuid, uuid, timestamptz, uuid, boolean) from public, anon, service_role;
grant execute on function public.reassign_active_case_to_vehicle_and_get_unified_payload_state(uuid, uuid, timestamptz, uuid, boolean) to authenticated;

insert into public.service_action_contracts (
  action_key, action_group, entity_scope, db_function_name, action_type, description,
  requires_authenticated_user, requires_aal2, writes_data, frontend_safe,
  internal_only, required_permission
) values
  ('case.continue_same_vehicle_and_load', 'case', 'reservation_case',
   'continue_case_same_vehicle_and_get_unified_payload_state', 'write',
   'Continue a case on the same vehicle and load its unified payload.',
   true, true, true, true, false, null),
  ('case.reassign_to_vehicle_and_load', 'case', 'reservation_case',
   'reassign_active_case_to_vehicle_and_get_unified_payload_state', 'write',
   'Reassign an active case to another vehicle and load its unified payload.',
   true, true, true, true, false, null)
on conflict (action_key) do update set
  action_group = excluded.action_group, entity_scope = excluded.entity_scope,
  db_function_name = excluded.db_function_name, action_type = excluded.action_type,
  description = excluded.description,
  requires_authenticated_user = excluded.requires_authenticated_user,
  requires_aal2 = excluded.requires_aal2, writes_data = excluded.writes_data,
  frontend_safe = excluded.frontend_safe, internal_only = excluded.internal_only,
  required_permission = excluded.required_permission, updated_at = now();

-- Exact live mutating-helper overloads remain service-role-only.
revoke execute on function public.continue_case_same_vehicle_state(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.continue_case_same_vehicle_state(uuid, timestamptz) to service_role;
revoke execute on function public.renew_reservation_same_vehicle_state(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.renew_reservation_same_vehicle_state(uuid, timestamptz) to service_role;
revoke execute on function public.renew_same_vehicle_state(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.renew_same_vehicle_state(uuid, timestamptz) to service_role;
revoke execute on function public.restart_reservation_same_vehicle_after_gap_state(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.restart_reservation_same_vehicle_after_gap_state(uuid, timestamptz) to service_role;
revoke execute on function public.restart_same_vehicle_after_gap(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.restart_same_vehicle_after_gap(uuid, uuid, timestamptz) to service_role;
revoke execute on function public.start_vehicle_use_state(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.start_vehicle_use_state(uuid, uuid, timestamptz) to service_role;
revoke execute on function public.reassign_active_case_to_vehicle_state(uuid, uuid, timestamptz, uuid, boolean) from public, anon, authenticated;
grant execute on function public.reassign_active_case_to_vehicle_state(uuid, uuid, timestamptz, uuid, boolean) to service_role;
revoke execute on function public.swap_reservation_vehicle_state(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.swap_reservation_vehicle_state(uuid, uuid, timestamptz) to service_role;
revoke execute on function public.swap_vehicle_state(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.swap_vehicle_state(uuid, uuid, timestamptz) to service_role;
revoke execute on function public.resolve_reservation_dependency_as_reassigned_state(uuid, uuid) from public, anon, authenticated;
grant execute on function public.resolve_reservation_dependency_as_reassigned_state(uuid, uuid) to service_role;
revoke execute on function public.resolve_transportation_event_dependency_as_reassigned_state(uuid, uuid) from public, anon, authenticated;
grant execute on function public.resolve_transportation_event_dependency_as_reassigned_state(uuid, uuid) to service_role;
revoke execute on function public.resolve_reservation_dependency_state(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.resolve_reservation_dependency_state(uuid, text, uuid) to service_role;
revoke execute on function public.resolve_linked_conflicts_for_dependency_state(uuid) from public, anon, authenticated;
grant execute on function public.resolve_linked_conflicts_for_dependency_state(uuid) to service_role;

revoke insert, update, delete on table
  public.reservation_vehicle_dependencies, public.reservation_conflicts
from public, anon, authenticated;
grant insert, update, delete on table
  public.reservation_vehicle_dependencies, public.reservation_conflicts
to service_role;

-- get_unified_case_payload_state and all other read contracts remain unchanged.
