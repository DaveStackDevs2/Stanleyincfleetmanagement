-- Reproduces the Fleet Board contracts already applied to the live project.

insert into public.admin_settings (setting_key, setting_value, description)
values (
  'fleet_board.pay_type_colors',
  '{}'::jsonb,
  'Admin-configured Fleet Board background and text colors keyed by pay type.'
)
on conflict (setting_key) do nothing;

insert into public.admin_setting_permissions (setting_key, required_permission)
values ('fleet_board.pay_type_colors', 'user_admin.manage')
on conflict (setting_key, required_permission) do nothing;

CREATE OR REPLACE FUNCTION public.get_fleet_board_state(p_range_start timestamp with time zone, p_range_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
begin
  select au.id
    into v_user_id
  from public.app_users au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_user_id is null then
    raise exception 'Fleet Board access denied'
      using errcode = '42501';
  end if;

  if p_range_start is null
     or p_range_end is null
     or p_range_end <= p_range_start
     or p_range_end - p_range_start > interval '32 days'
  then
    raise exception 'Invalid Fleet Board date range'
      using errcode = '22023';
  end if;

  return jsonb_build_object(
    'status',
    'fleet_board_ready',
    'range_start',
    p_range_start,
    'range_end',
    p_range_end,

    'vehicles',
    (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', v.id,
            'stock_number', v.stock_number,
            'model_year', v.model_year,
            'model', v.model,
            'fleet_type', v.fleet_type,
            'status', v.status,
            'location', v.location
          )
          order by v.fleet_type, v.model, v.stock_number, v.id
        ),
        '[]'::jsonb
      )
      from public.vehicles v
    ),

    'reservations',
    (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'vehicle_id', r.vehicle_id,
            'start_date', r.start_date,
            'expected_return_datetime', r.expected_return_datetime,
            'status', r.status,
            'reservation_type', r.reservation_type,
            'requested_model', r.requested_model
          )
          order by r.start_date, r.id
        ),
        '[]'::jsonb
      )
      from public.reservations r
      where r.vehicle_id is null
        and lower(coalesce(r.reservation_type, '')) = 'rental'
        and lower(coalesce(r.status, '')) <> 'cancelled'
        and r.start_date < p_range_end
        and r.expected_return_datetime > p_range_start
    ),

    'capacities',
    (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'vehicle_class', l.vehicle_class,
            'daily_limit', l.daily_limit
          )
          order by l.vehicle_class
        ),
        '[]'::jsonb
      )
      from public.rental_model_limits l
    ),

    'assignments',
    (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'transportation_event_id', t.transportation_event_id,
            'vehicle_id', t.vehicle_id,
            'source_type', t.source_type,
            'transportation_event_status',
              t.transportation_event_status,
            'actual_out_at', t.actual_out_at,
            'actual_in_at', t.actual_in_at,
            'expected_return_at', t.expected_return_at,
            'current_billing_start_time',
              t.current_billing_start_time,
            'current_billing_end_time',
              t.current_billing_end_time,
            'current_billing_pay_type',
              t.current_billing_pay_type,
            'current_conflict_id', t.current_conflict_id,
            'current_conflict_is_resolved',
              t.current_conflict_is_resolved
          )
          order by
            coalesce(
              t.actual_out_at,
              t.current_billing_start_time
            ),
            t.transportation_event_id
        ),
        '[]'::jsonb
      )
      from public.v_transportation_event_unified_operational_state t
      where t.vehicle_id is not null
        and coalesce(
          t.actual_out_at,
          t.current_billing_start_time
        ) is not null
        and coalesce(
          t.actual_out_at,
          t.current_billing_start_time
        ) < p_range_end
        and coalesce(
          t.actual_in_at,
          t.expected_return_at,
          t.current_billing_end_time,
          'infinity'::timestamptz
        ) > p_range_start
    ),

    'pay_type_colors',
    coalesce(
      (
        select s.setting_value
        from public.admin_settings s
        where s.setting_key = 'fleet_board.pay_type_colors'
        limit 1
      ),
      '{}'::jsonb
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_fleet_board_pay_type_colors_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
  v_access jsonb;
  v_colors jsonb;
  v_pay_types jsonb;
begin
  select au.id
    into v_user_id
  from public.app_users au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_user_id is null then
    raise exception 'Fleet Board color access denied'
      using errcode = '42501';
  end if;

  v_access :=
    public.get_user_admin_setting_access_state(
      v_user_id,
      'fleet_board.pay_type_colors'
    );

  select coalesce(setting_value, '{}'::jsonb)
    into v_colors
  from public.admin_settings
  where setting_key = 'fleet_board.pay_type_colors';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'pay_type', rule.pay_type,
        'description', rule.description,
        'sort_order', rule.sort_order
      )
      order by rule.sort_order, rule.pay_type
    ),
    '[]'::jsonb
  )
    into v_pay_types
  from public.pay_type_rules rule
  where rule.is_active = true
    and rule.active = true;

  return jsonb_build_object(
    'status',
    'fleet_board_pay_type_colors_ready',
    'can_manage',
    coalesce((v_access ->> 'allowed')::boolean, false),
    'pay_types',
    v_pay_types,
    'colors',
    coalesce(v_colors, '{}'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_fleet_board_pay_type_colors_state(p_colors jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
  v_access jsonb;
begin
  select au.id
    into v_user_id
  from public.app_users au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_user_id is null then
    raise exception 'Fleet Board color access denied'
      using errcode = '42501';
  end if;

  v_access :=
    public.get_user_admin_setting_access_state(
      v_user_id,
      'fleet_board.pay_type_colors'
    );

  if coalesce((v_access ->> 'allowed')::boolean, false) is not true then
    raise exception 'Fleet Board color access denied'
      using errcode = '42501';
  end if;

  if p_colors is null
     or jsonb_typeof(p_colors) <> 'object'
  then
    raise exception 'Invalid Fleet Board color configuration'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each(p_colors) entry
    where jsonb_typeof(entry.value) <> 'object'
       or entry.value ->> 'background_color'
          !~ '^#[0-9A-Fa-f]{6}$'
       or entry.value ->> 'text_color'
          !~ '^#[0-9A-Fa-f]{6}$'
       or (entry.value - 'background_color' - 'text_color')
          <> '{}'::jsonb
       or not exists (
         select 1
         from public.pay_type_rules rule
         where rule.pay_type = entry.key
           and rule.is_active = true
           and rule.active = true
       )
  ) then
    raise exception 'Invalid Fleet Board color configuration'
      using errcode = '22023';
  end if;

  update public.admin_settings
  set setting_value = p_colors
  where setting_key = 'fleet_board.pay_type_colors';

  if not found then
    raise exception 'Fleet Board color setting not found'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'status',
    'fleet_board_pay_type_colors_saved',
    'setting_key',
    'fleet_board.pay_type_colors',
    'colors',
    p_colors
  );
end;
$function$;

revoke all on function public.get_fleet_board_state(timestamptz, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.get_fleet_board_pay_type_colors_state() from public, anon, authenticated, service_role;
revoke all on function public.set_fleet_board_pay_type_colors_state(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.get_fleet_board_state(timestamptz, timestamptz) to authenticated, service_role;
grant execute on function public.get_fleet_board_pay_type_colors_state() to authenticated, service_role;
grant execute on function public.set_fleet_board_pay_type_colors_state(jsonb) to authenticated, service_role;
