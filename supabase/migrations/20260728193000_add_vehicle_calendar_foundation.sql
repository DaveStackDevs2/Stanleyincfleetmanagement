-- Phase 3: permission-protected, visible-range vehicle calendar foundation.

insert into public.permissions (permission_key, description)
values
  ('calendar.view', 'View the vehicle calendar'),
  ('calendar.create', 'Create vehicle calendar events'),
  ('calendar.edit', 'Edit vehicle calendar events'),
  ('calendar.delete', 'Delete vehicle calendar events'),
  ('calendar.configure_colors', 'Configure vehicle calendar colors')
on conflict (permission_key) do update set description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select managing_roles.role_id, calendar_permissions.id
from (
  select rp.role_id
  from public.role_permissions rp
  join public.permissions p on p.id = rp.permission_id
  where p.permission_key = 'user_admin.manage'
) managing_roles
cross join public.permissions calendar_permissions
where calendar_permissions.permission_key like 'calendar.%'
on conflict (role_id, permission_id) do nothing;

create table if not exists public.calendar_event_types (
  event_type text primary key check (event_type in ('reservation', 'quote', 'maintenance')),
  label text not null unique,
  sort_order integer not null,
  is_active boolean not null default true
);

insert into public.calendar_event_types (event_type, label, sort_order) values
  ('reservation', 'Reservation', 10), ('quote', 'Quote', 20), ('maintenance', 'Maintenance', 30)
on conflict (event_type) do update set label=excluded.label, sort_order=excluded.sort_order;

create table if not exists public.calendar_colors (
  color_key text primary key,
  color_group text not null check (color_group in ('event_type', 'pay_type')),
  label text not null,
  background_color text not null check (background_color ~ '^#[0-9A-Fa-f]{6}$'),
  text_color text not null check (text_color ~ '^#[0-9A-Fa-f]{6}$'),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.app_users(id)
);

insert into public.calendar_colors (color_key, color_group, label, background_color, text_color) values
  ('event:reservation', 'event_type', 'Reservation', '#005EB8', '#FFFFFF'),
  ('event:quote', 'event_type', 'Quote', '#6F4E89', '#FFFFFF'),
  ('event:maintenance', 'event_type', 'Maintenance', '#D97706', '#FFFFFF'),
  ('pay:customer', 'pay_type', 'Customer', '#D7E8F7', '#16324F'),
  ('pay:warranty', 'pay_type', 'Warranty', '#DCEFE1', '#174D2A')
on conflict (color_key) do nothing;

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id),
  event_type text not null references public.calendar_event_types(event_type),
  customer_name text not null check (btrim(customer_name) <> ''),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  pay_type text,
  status text not null,
  reference_number text,
  vehicle_year integer,
  vehicle_make text,
  vehicle_model text,
  has_conflict boolean not null default false,
  is_overdue boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.app_users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.app_users(id),
  constraint calendar_events_valid_range check (starts_at < ends_at)
);

create index if not exists calendar_events_visible_range_idx on public.calendar_events (starts_at, ends_at);
create index if not exists calendar_events_vehicle_range_idx on public.calendar_events (vehicle_id, starts_at, ends_at);

alter table public.calendar_event_types enable row level security;
alter table public.calendar_colors enable row level security;
alter table public.calendar_events enable row level security;
revoke all on public.calendar_event_types, public.calendar_colors, public.calendar_events from anon, authenticated;

create or replace function public.require_calendar_permission(p_permission text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid;
begin
  select id into v_actor from public.app_users where auth_user_id = auth.uid() and is_active = true;
  if v_actor is null or not exists (
    select 1 from public.v_user_effective_permissions where user_id = v_actor and permission_key = p_permission
  ) then raise exception 'Calendar permission required' using errcode = '42501'; end if;
  return v_actor;
end; $$;

create or replace function public.get_vehicle_calendar_state(p_range_start timestamptz, p_range_end timestamptz)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.require_calendar_permission('calendar.view');
  if p_range_start is null or p_range_end is null or p_range_start >= p_range_end or
     p_range_end - p_range_start > interval '32 days' then raise exception 'Invalid visible range'; end if;
  return jsonb_build_object(
    'status', 'vehicle_calendar_ready', 'range_start', p_range_start, 'range_end', p_range_end,
    'vehicles', coalesce((select jsonb_agg(jsonb_build_object(
      'id', v.id, 'stock_number', v.stock_number, 'model', v.model, 'fleet_type', v.fleet_type,
      'status', v.status, 'location', v.location, 'is_active', true
    ) order by case when lower(v.fleet_type) like '%loaner%' then 0 else 1 end, v.stock_number)
      from public.vehicles v), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'vehicle_id', e.vehicle_id, 'event_type', e.event_type, 'customer_name', e.customer_name,
      'starts_at', e.starts_at, 'ends_at', e.ends_at, 'pay_type', e.pay_type, 'status', e.status,
      'reference_number', e.reference_number, 'vehicle_year', e.vehicle_year, 'vehicle_make', e.vehicle_make,
      'vehicle_model', coalesce(e.vehicle_model, v.model), 'stock_number', v.stock_number,
      'has_conflict', e.has_conflict, 'is_overdue', e.is_overdue,
      'background_color', coalesce(pc.background_color, ec.background_color, '#005EB8'),
      'text_color', coalesce(pc.text_color, ec.text_color, '#FFFFFF')
    ) order by e.starts_at) from public.calendar_events e join public.vehicles v on v.id = e.vehicle_id
      left join public.calendar_colors ec on ec.color_key = 'event:' || e.event_type
      left join public.calendar_colors pc on pc.color_key = 'pay:' || lower(coalesce(e.pay_type, ''))
      where e.starts_at < p_range_end and e.ends_at > p_range_start), '[]'::jsonb),
    'event_types', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from public.calendar_event_types t where t.is_active), '[]'::jsonb),
    'colors', coalesce((select jsonb_agg(to_jsonb(c) order by c.color_group, c.label) from public.calendar_colors c), '[]'::jsonb)
  );
end; $$;

create or replace function public.save_calendar_event_state(
  p_event_id uuid, p_vehicle_id uuid, p_event_type text, p_customer_name text,
  p_starts_at timestamptz, p_ends_at timestamptz, p_pay_type text, p_status text,
  p_reference_number text default null, p_vehicle_year integer default null,
  p_vehicle_make text default null, p_vehicle_model text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid; v_id uuid := coalesce(p_event_id, gen_random_uuid()); v_old public.calendar_events%rowtype;
begin
  v_actor := public.require_calendar_permission(case when p_event_id is null then 'calendar.create' else 'calendar.edit' end);
  if p_event_id is not null then
    select * into v_old from public.calendar_events where id = p_event_id for update;
    if not found then raise exception 'Calendar event not found'; end if;
  end if;
  if p_vehicle_id is null or p_starts_at is null or p_ends_at is null or p_starts_at >= p_ends_at or
     nullif(btrim(p_customer_name), '') is null or nullif(btrim(p_status), '') is null or
     not exists (select 1 from public.calendar_event_types where event_type = p_event_type and is_active) then
    raise exception 'Invalid calendar event';
  end if;
  if p_event_id is not null and v_old.vehicle_id <> p_vehicle_id then
    perform pg_advisory_xact_lock(least(hashtextextended(v_old.vehicle_id::text, 0), hashtextextended(p_vehicle_id::text, 0)));
    perform pg_advisory_xact_lock(greatest(hashtextextended(v_old.vehicle_id::text, 0), hashtextextended(p_vehicle_id::text, 0)));
  else
    perform pg_advisory_xact_lock(hashtextextended(p_vehicle_id::text, 0));
  end if;
  if not exists (select 1 from public.vehicles where id = p_vehicle_id and lower(status) not in ('maintenance','recon_hold','hard_block')) then
    raise exception 'Vehicle is unavailable';
  end if;
  if exists (select 1 from public.calendar_events where vehicle_id = p_vehicle_id and id <> v_id
    and starts_at < p_ends_at and ends_at > p_starts_at) then raise exception 'Calendar event conflict'; end if;
  insert into public.calendar_events (id, vehicle_id, event_type, customer_name, starts_at, ends_at, pay_type,
    status, reference_number, vehicle_year, vehicle_make, vehicle_model, created_by, updated_by)
  values (v_id, p_vehicle_id, p_event_type, btrim(p_customer_name), p_starts_at, p_ends_at, p_pay_type,
    btrim(p_status), p_reference_number, p_vehicle_year, p_vehicle_make, p_vehicle_model, v_actor, v_actor)
  on conflict (id) do update set vehicle_id=excluded.vehicle_id, event_type=excluded.event_type,
    customer_name=excluded.customer_name, starts_at=excluded.starts_at, ends_at=excluded.ends_at,
    pay_type=excluded.pay_type, status=excluded.status, reference_number=excluded.reference_number,
    vehicle_year=excluded.vehicle_year, vehicle_make=excluded.vehicle_make, vehicle_model=excluded.vehicle_model,
    updated_at=now(), updated_by=v_actor;
  insert into public.audit_log (entity_type, entity_id, action_type, old_value, new_value, metadata, actor_user_id)
  values ('calendar_event', v_id::text, case when p_event_id is null then 'create' else 'update' end,
    case when p_event_id is null then null else to_jsonb(v_old)::text end,
    (select to_jsonb(e)::text from public.calendar_events e where e.id=v_id),
    jsonb_build_object('source','vehicle_calendar'), v_actor::text);
  return jsonb_build_object('status', 'calendar_event_saved', 'event_id', v_id);
end; $$;

create or replace function public.delete_calendar_event_state(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid; v_old public.calendar_events%rowtype;
begin
  v_actor := public.require_calendar_permission('calendar.delete');
  delete from public.calendar_events where id = p_event_id returning * into v_old;
  if not found then raise exception 'Calendar event not found'; end if;
  insert into public.audit_log (entity_type, entity_id, action_type, old_value, metadata, actor_user_id)
  values ('calendar_event', p_event_id::text, 'delete', to_jsonb(v_old)::text,
    jsonb_build_object('source','vehicle_calendar'), v_actor::text);
  return jsonb_build_object('status', 'calendar_event_deleted');
end; $$;

create or replace function public.set_calendar_color_state(p_color_key text, p_background_color text, p_text_color text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid; v_old jsonb; v_new jsonb;
begin
  v_actor := public.require_calendar_permission('calendar.configure_colors');
  if p_background_color !~ '^#[0-9A-Fa-f]{6}$' or p_text_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid color'; end if;
  select to_jsonb(c) into v_old from public.calendar_colors c where color_key=p_color_key for update;
  update public.calendar_colors c set background_color=p_background_color, text_color=p_text_color,
    updated_at=now(), updated_by=v_actor where c.color_key=p_color_key returning to_jsonb(c) into v_new;
  if not found then raise exception 'Calendar color not found'; end if;
  insert into public.audit_log (entity_type, entity_id, action_type, old_value, new_value, metadata, actor_user_id)
  values ('calendar_color', p_color_key, 'update', v_old::text, v_new::text,
    jsonb_build_object('source','vehicle_calendar'), v_actor::text);
  return jsonb_build_object('status', 'calendar_color_updated');
end; $$;

revoke all on function public.require_calendar_permission(text) from public, anon, authenticated;
revoke all on function public.get_vehicle_calendar_state(timestamptz, timestamptz) from public, anon;
revoke all on function public.save_calendar_event_state(uuid, uuid, text, text, timestamptz, timestamptz, text, text, text, integer, text, text) from public, anon;
revoke all on function public.delete_calendar_event_state(uuid) from public, anon;
revoke all on function public.set_calendar_color_state(text, text, text) from public, anon;
grant execute on function public.get_vehicle_calendar_state(timestamptz, timestamptz) to authenticated;
grant execute on function public.save_calendar_event_state(uuid, uuid, text, text, timestamptz, timestamptz, text, text, text, integer, text, text) to authenticated;
grant execute on function public.delete_calendar_event_state(uuid) to authenticated;
grant execute on function public.set_calendar_color_state(text, text, text) to authenticated;
