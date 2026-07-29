-- Reproduces the Fleet Board contracts already applied to the live project.

insert into public.admin_settings (setting_key, setting_value, description)
values (
  'fleet_board.pay_type_colors',
  '{}'::jsonb,
  'Fleet Board pay-type background and text colors keyed by pay type.'
)
on conflict (setting_key) do nothing;

insert into public.admin_setting_permissions (setting_key, required_permission)
values ('fleet_board.pay_type_colors', 'user_admin.manage')
on conflict (setting_key, required_permission) do nothing;

create or replace function public.get_fleet_board_state(p_range_start timestamptz, p_range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_colors jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_users
    where auth_user_id = auth.uid() and is_active = true
  ) then
    raise exception 'Active application user required' using errcode = '42501';
  end if;

  if p_range_start is null or p_range_end is null or p_range_end <= p_range_start then
    raise exception 'A valid Fleet Board range is required' using errcode = '22023';
  end if;

  if p_range_end > p_range_start + interval '32 days' then
    raise exception 'Fleet Board range cannot exceed 32 days' using errcode = '22023';
  end if;

  select setting_value into v_colors
  from public.admin_settings
  where setting_key = 'fleet_board.pay_type_colors';

  return jsonb_build_object(
    'status', 'fleet_board_ready',
    'range_start', p_range_start,
    'range_end', p_range_end,
    'vehicles', coalesce((
      select jsonb_agg(to_jsonb(v) order by v.fleet_type, v.model, v.stock_number)
      from (
        select id, stock_number, model, model_year, fleet_type, status, location
        from public.vehicles
      ) v
    ), '[]'::jsonb),
    'assignments', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.actual_out_at nulls last, a.current_billing_start_time nulls last, a.transportation_event_id)
      from (
        select transportation_event_id, vehicle_id, source_type,
          transportation_event_status, actual_out_at, actual_in_at,
          expected_return_at, current_billing_start_time,
          current_billing_end_time, current_billing_pay_type,
          current_conflict_id, current_conflict_is_resolved
        from public.v_transportation_event_unified_operational_state
        where vehicle_id is not null
          and coalesce(actual_out_at, current_billing_start_time) < p_range_end
          and coalesce(actual_in_at, expected_return_at, current_billing_end_time, 'infinity'::timestamptz) > p_range_start
      ) a
    ), '[]'::jsonb),
    'reservations', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.start_date, r.id)
      from (
        select id, vehicle_id, start_date, expected_return_datetime, status,
          requested_model, reservation_type
        from public.reservations
        where vehicle_id is null
          and reservation_type = 'rental'
          and status <> 'cancelled'
          and start_date < p_range_end
          and expected_return_datetime > p_range_start
      ) r
    ), '[]'::jsonb),
    'capacities', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.vehicle_class)
      from (
        select vehicle_class, daily_limit
        from public.rental_model_limits
      ) c
    ), '[]'::jsonb),
    'pay_type_colors', coalesce(v_colors, '{}'::jsonb)
  );
end;
$$;

create or replace function public.get_fleet_board_pay_type_colors_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_colors jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_users
    where auth_user_id = auth.uid() and is_active = true
  ) then
    raise exception 'Active application user required' using errcode = '42501';
  end if;

  select setting_value into v_colors
  from public.admin_settings
  where setting_key = 'fleet_board.pay_type_colors';

  return jsonb_build_object(
    'status', 'fleet_board_pay_type_colors_ready',
    'colors', coalesce(v_colors, '{}'::jsonb)
  );
end;
$$;

create or replace function public.set_fleet_board_pay_type_colors_state(p_colors jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
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

  if p_colors is null or jsonb_typeof(p_colors) <> 'object' or exists (
    select 1
    from jsonb_each(p_colors) entry
    where not exists (
        select 1
        from public.pay_type_rules ptr
        where ptr.pay_type = entry.key and ptr.is_active = true
      )
      or jsonb_typeof(entry.value) <> 'object'
      or array(select jsonb_object_keys(entry.value) order by 1) <> array['background_color', 'text_color']::text[]
      or not (entry.value ->> 'background_color' ~ '^#[0-9A-Fa-f]{6}$')
      or not (entry.value ->> 'text_color' ~ '^#[0-9A-Fa-f]{6}$')
  ) then
    raise exception 'Pay-type colors must contain only active pay types and exact six-digit hex color pairs' using errcode = '22023';
  end if;

  update public.admin_settings
  set setting_value = p_colors
  where setting_key = 'fleet_board.pay_type_colors';

  return jsonb_build_object(
    'status', 'fleet_board_pay_type_colors_updated',
    'colors', p_colors
  );
end;
$$;

revoke all on function public.get_fleet_board_state(timestamptz, timestamptz) from public, anon;
revoke all on function public.get_fleet_board_pay_type_colors_state() from public, anon;
revoke all on function public.set_fleet_board_pay_type_colors_state(jsonb) from public, anon;
grant execute on function public.get_fleet_board_state(timestamptz, timestamptz) to authenticated, service_role;
grant execute on function public.get_fleet_board_pay_type_colors_state() to authenticated, service_role;
grant execute on function public.set_fleet_board_pay_type_colors_state(jsonb) to authenticated, service_role;
