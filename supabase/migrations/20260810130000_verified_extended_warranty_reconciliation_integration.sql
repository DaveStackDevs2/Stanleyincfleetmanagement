-- Record the verified live Extended Warranty reconciliation integration.
-- This migration contains no provider, rate, cap, customer, vehicle, RO, or test data.

insert into public.permissions (permission_key, description)
values (
  'billing.extended_warranty_reconcile',
  'Can reconcile Extended Warranty coverage before loading authoritative Billing state'
)
on conflict (permission_key) do update
set description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
cross join public.permissions permission
where role.role_name = 'Dev'
  and permission.permission_key = 'billing.extended_warranty_reconcile'
on conflict do nothing;

-- Preserve the established payload engine body and restrict its execution boundary.
alter function public.reconcile_extended_warranty_coverage_and_get_state(uuid)
  owner to postgres;
alter function public.reconcile_extended_warranty_coverage_and_get_state(uuid)
  security definer;
alter function public.reconcile_extended_warranty_coverage_and_get_state(uuid)
  set search_path to '';
revoke execute on function public.reconcile_extended_warranty_coverage_and_get_state(uuid)
  from public, anon, authenticated;
grant execute on function public.reconcile_extended_warranty_coverage_and_get_state(uuid)
  to postgres, service_role;

create or replace function public.reconcile_extended_warranty_coverage_and_get_payload_state(
  p_transportation_event_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_user_id uuid;
begin
  if p_transportation_event_id is null then
    raise exception 'Transportation event is required'
      using errcode = '22023';
  end if;

  select app_user.id
  into v_actor_user_id
  from public.app_users app_user
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active = true;

  if v_actor_user_id is null then
    raise exception 'An active application user is required'
      using errcode = '42501';
  end if;

  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'AAL2 authentication is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.v_user_effective_permissions permission
    where permission.user_id = v_actor_user_id
      and permission.permission_key = 'billing.extended_warranty_reconcile'
  ) then
    raise exception 'Extended Warranty reconciliation permission is required'
      using errcode = '42501';
  end if;

  return public.reconcile_extended_warranty_coverage_and_get_state(
    p_transportation_event_id
  );
end;
$function$;

alter function public.reconcile_extended_warranty_coverage_and_get_payload_state(uuid)
  owner to postgres;
revoke all on function public.reconcile_extended_warranty_coverage_and_get_payload_state(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.reconcile_extended_warranty_coverage_and_get_payload_state(uuid)
  to authenticated, service_role;

create or replace function public.get_reconciled_billing_workspace_state(
  p_effective_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_user_id uuid;
  v_now timestamptz;
  v_transportation_event_id uuid;
begin
  if p_effective_at is null then
    raise exception 'Workspace timestamp is required'
      using errcode = '22023';
  end if;

  v_now := clock_timestamp();
  if p_effective_at > v_now then
    raise exception 'Workspace reconciliation timestamp cannot be in the future'
      using errcode = '22023';
  end if;

  select app_user.id
  into v_actor_user_id
  from public.app_users app_user
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active = true;

  if v_actor_user_id is null then
    raise exception 'An active application user is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.v_user_effective_permissions permission
    where permission.user_id = v_actor_user_id
      and permission.permission_key = 'billing.extended_warranty_reconcile'
  ) then
    raise exception 'Extended Warranty reconciliation permission is required'
      using errcode = '42501';
  end if;

  for v_transportation_event_id in
    select warranty_case.transportation_event_id
    from public.warranty_cases warranty_case
    join public.transportation_events transportation_event
      on transportation_event.id = warranty_case.transportation_event_id
    where lower(btrim(transportation_event.status)) = 'active'
    order by warranty_case.transportation_event_id
  loop
    perform public.reconcile_extended_warranty_coverage_state(
      v_transportation_event_id,
      p_effective_at
    );
  end loop;

  return public.get_billing_workspace_state(p_effective_at);
end;
$function$;

alter function public.get_reconciled_billing_workspace_state(timestamptz)
  owner to postgres;
revoke all on function public.get_reconciled_billing_workspace_state(timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.get_reconciled_billing_workspace_state(timestamptz)
  to authenticated, service_role;
