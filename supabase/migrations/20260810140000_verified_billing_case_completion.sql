-- Record the verified live Billing Complete / Return Case authorization contract.
-- This migration contains no customer, vehicle, RO, rental, rate, provider, or UUID fixtures.

insert into public.permissions (permission_key, description)
values (
  'billing.case_complete',
  'Can return the assigned vehicle, close billing, and complete a transportation case'
)
on conflict (permission_key) do update
set description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
cross join public.permissions permission
where role.role_name = 'Dev'
  and permission.permission_key = 'billing.case_complete'
on conflict do nothing;

create or replace function public.complete_case_and_get_unified_payload_state(
  p_reservation_id uuid,
  p_actual_in_at timestamptz,
  p_end_mileage integer default null::integer,
  p_close_billing boolean default true,
  p_close_note text default null::text,
  p_closed_by uuid default null::uuid
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid;
  v_existing_end_mileage integer;
  v_effective_end_mileage integer;
  v_completion_result jsonb;
  v_unified_payload jsonb;
begin
  select au.id
  into v_user_id
  from public.app_users au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_user_id is null then
    raise exception 'Billing action access denied'
      using errcode = '42501';
  end if;

  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'Billing action requires AAL2'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.v_user_effective_permissions permission
    where permission.user_id = v_user_id
      and permission.permission_key = 'billing.case_complete'
  ) then
    raise exception 'Case completion permission is required'
      using errcode = '42501';
  end if;

  if p_closed_by is not null
     and p_closed_by <> v_user_id then
    raise exception 'Billing actor mismatch'
      using errcode = '42501';
  end if;

  select r.end_mileage
  into v_existing_end_mileage
  from public.reservations r
  where r.id = p_reservation_id
  for update;

  if not found then
    raise exception 'Reservation % does not exist', p_reservation_id;
  end if;

  v_effective_end_mileage := coalesce(p_end_mileage, v_existing_end_mileage);

  v_completion_result := public.complete_case_return_and_close_state(
    p_reservation_id,
    p_actual_in_at,
    v_effective_end_mileage,
    p_close_billing,
    p_close_note,
    v_user_id
  );

  v_unified_payload := public.get_unified_case_payload_state(p_reservation_id);

  return jsonb_build_object(
    'status', 'case_completed_and_loaded',
    'reservation_id', p_reservation_id,
    'completion_result', v_completion_result,
    'unified_case_payload', v_unified_payload
  );
end;
$function$;

alter function public.complete_case_and_get_unified_payload_state(uuid, timestamptz, integer, boolean, text, uuid)
  owner to postgres;
revoke all on function public.complete_case_and_get_unified_payload_state(uuid, timestamptz, integer, boolean, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_case_and_get_unified_payload_state(uuid, timestamptz, integer, boolean, text, uuid)
  to authenticated;
