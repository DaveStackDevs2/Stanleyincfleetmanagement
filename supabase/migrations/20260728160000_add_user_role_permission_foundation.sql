-- Phase 2: single-role user administration with additive grants and explicit denies.

create table if not exists public.user_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  effect text not null check (effect in ('grant', 'deny')),
  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id),
  unique (user_id, permission_id)
);

delete from public.user_roles
where id in (
  select id from (
    select id, row_number() over (partition by user_id order by created_at desc nulls last, id desc) as position
    from public.user_roles where user_id is not null
  ) ranked where position > 1
);

create unique index if not exists user_roles_one_role_per_user
  on public.user_roles (user_id);
delete from public.role_permissions
where id in (
  select id from (
    select id, row_number() over (partition by role_id, permission_id order by created_at desc nulls last, id desc) as position
    from public.role_permissions where role_id is not null and permission_id is not null
  ) ranked where position > 1
);
create unique index if not exists role_permissions_role_permission_key
  on public.role_permissions (role_id, permission_id);

insert into public.roles (role_name, description, is_system_role)
values
  ('Dev Admin', 'Development administration', true),
  ('Admin', 'Application administration', true),
  ('CTP Staff', 'CTP operations staff', true),
  ('Service Manager', 'Service management', true),
  ('Sales Management', 'Sales management', true),
  ('Service Advisor', 'Service advisory staff', true),
  ('Sales Staff', 'Sales staff', true)
on conflict (role_name) do update
set is_system_role = true;

insert into public.permissions (permission_key, description)
values ('user_admin.manage', 'Manage users, roles, and permissions')
on conflict (permission_key) do update
set description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.role_name in ('Dev Admin', 'Admin')
  and p.permission_key = 'user_admin.manage'
on conflict (role_id, permission_id) do nothing;

create or replace view public.v_user_effective_permissions
with (security_invoker = true) as
select distinct u.id as user_id, p.permission_key
from public.app_users u
join public.permissions p on (
  exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    where ur.user_id = u.id and rp.permission_id = p.id
  )
  or exists (
    select 1 from public.user_permission_overrides upo
    where upo.user_id = u.id
      and upo.permission_id = p.id
      and upo.effect = 'grant'
  )
)
where not exists (
  select 1 from public.user_permission_overrides upo
  where upo.user_id = u.id
    and upo.permission_id = p.id
    and upo.effect = 'deny'
);

create or replace function public.require_user_admin_permission()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_actor_id uuid;
begin
  select id into v_actor_id
  from public.app_users
  where auth_user_id = auth.uid() and is_active = true;

  if v_actor_id is null or not exists (
    select 1 from public.v_user_effective_permissions
    where user_id = v_actor_id and permission_key = 'user_admin.manage'
  ) then
    raise exception 'User administration permission required' using errcode = '42501';
  end if;
  return v_actor_id;
end;
$$;

create or replace function public.get_current_user_effective_permissions_state()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_user_id uuid;
begin
  select id into v_user_id from public.app_users
  where auth_user_id = auth.uid() and is_active = true;
  if v_user_id is null then raise exception 'Active application user not found' using errcode = '42501'; end if;
  return jsonb_build_object(
    'status', 'effective_permissions_ready',
    'user_id', v_user_id,
    'permission_keys', coalesce((select jsonb_agg(permission_key order by permission_key)
      from public.v_user_effective_permissions where user_id = v_user_id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_user_management_state()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_result jsonb;
begin
  perform public.require_user_admin_permission();
  select jsonb_build_object(
    'status', 'user_management_ready',
    'permissions', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'key', p.permission_key, 'description', p.description
    ) order by p.permission_key) from public.permissions p), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'name', r.role_name, 'description', r.description,
      'permission_keys', coalesce((select jsonb_agg(p.permission_key order by p.permission_key)
        from public.role_permissions rp join public.permissions p on p.id = rp.permission_id
        where rp.role_id = r.id), '[]'::jsonb)
    ) order by r.role_name) from public.roles r), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'email', u.email, 'full_name', u.full_name, 'is_active', u.is_active,
      'role_id', ur.role_id,
      'granted_permission_keys', coalesce((select jsonb_agg(p.permission_key order by p.permission_key)
        from public.user_permission_overrides o join public.permissions p on p.id = o.permission_id
        where o.user_id = u.id and o.effect = 'grant'), '[]'::jsonb),
      'denied_permission_keys', coalesce((select jsonb_agg(p.permission_key order by p.permission_key)
        from public.user_permission_overrides o join public.permissions p on p.id = o.permission_id
        where o.user_id = u.id and o.effect = 'deny'), '[]'::jsonb),
      'effective_permission_keys', coalesce((select jsonb_agg(ep.permission_key order by ep.permission_key)
        from public.v_user_effective_permissions ep where ep.user_id = u.id), '[]'::jsonb)
    ) order by u.email) from public.app_users u left join public.user_roles ur on ur.user_id = u.id), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.set_user_role_state(p_user_id uuid, p_role_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.require_user_admin_permission();
  if not exists (select 1 from public.app_users where id = p_user_id) or
     not exists (select 1 from public.roles where id = p_role_id) then
    raise exception 'User or role not found';
  end if;
  insert into public.user_roles (user_id, role_id) values (p_user_id, p_role_id)
  on conflict (user_id) do update set role_id = excluded.role_id;
  return jsonb_build_object('status', 'user_role_updated');
end; $$;

create or replace function public.set_user_permission_override_state(
  p_user_id uuid, p_permission_id uuid, p_effect text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid;
begin
  v_actor := public.require_user_admin_permission();
  if p_effect is not null and p_effect not in ('grant', 'deny') then raise exception 'Invalid effect'; end if;
  if not exists (select 1 from public.app_users where id = p_user_id) or
     not exists (select 1 from public.permissions where id = p_permission_id) then
    raise exception 'User or permission not found';
  end if;
  if p_effect is null then
    delete from public.user_permission_overrides where user_id = p_user_id and permission_id = p_permission_id;
  else
    insert into public.user_permission_overrides (user_id, permission_id, effect, created_by)
    values (p_user_id, p_permission_id, p_effect, v_actor)
    on conflict (user_id, permission_id) do update set effect = excluded.effect, created_by = excluded.created_by, created_at = now();
  end if;
  return jsonb_build_object('status', 'user_permission_override_updated');
end; $$;

create or replace function public.set_role_permission_state(
  p_role_id uuid, p_permission_id uuid, p_enabled boolean
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.require_user_admin_permission();
  if not exists (select 1 from public.roles where id = p_role_id) or
     not exists (select 1 from public.permissions where id = p_permission_id) then
    raise exception 'Role or permission not found';
  end if;
  if p_enabled then
    insert into public.role_permissions (role_id, permission_id) values (p_role_id, p_permission_id)
    on conflict (role_id, permission_id) do nothing;
  else
    delete from public.role_permissions where role_id = p_role_id and permission_id = p_permission_id;
  end if;
  return jsonb_build_object('status', 'role_permission_updated');
end; $$;

revoke all on public.user_permission_overrides from anon, authenticated;
revoke all on function public.require_user_admin_permission() from public, anon, authenticated;
revoke all on function public.get_current_user_effective_permissions_state() from public, anon;
revoke all on function public.get_user_management_state() from public, anon;
revoke all on function public.set_user_role_state(uuid, uuid) from public, anon;
revoke all on function public.set_user_permission_override_state(uuid, uuid, text) from public, anon;
revoke all on function public.set_role_permission_state(uuid, uuid, boolean) from public, anon;
grant execute on function public.get_user_management_state() to authenticated;
grant execute on function public.get_current_user_effective_permissions_state() to authenticated;
grant execute on function public.set_user_role_state(uuid, uuid) to authenticated;
grant execute on function public.set_user_permission_override_state(uuid, uuid, text) to authenticated;
grant execute on function public.set_role_permission_state(uuid, uuid, boolean) to authenticated;
revoke all on public.v_user_effective_permissions from anon, authenticated;
