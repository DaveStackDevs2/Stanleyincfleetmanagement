-- Extend the existing Fleet Board read engine as an operational router.
-- This migration is intentionally not applied to production by this checkpoint.

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
            'requested_model', r.requested_model,
            'transportation_event_id', r.transportation_event_id,
            'customer_name', c.name,
            'ro_number', r.ro_number,
            'service_advisor', r.service_advisor
          )
          order by r.start_date, r.id
        ),
        '[]'::jsonb
      )
      from public.reservations r
      join public.transportation_events te
        on te.id = r.transportation_event_id
       and te.status = 'active'
      join public.rental_pricing_agreements a
        on a.reservation_id = r.id
       and a.transportation_event_id = r.transportation_event_id
       and a.is_active = true
       and a.pricing_started_at is null
      left join public.customers c on c.id = r.customer_id
      where r.vehicle_id is null
        and lower(btrim(coalesce(r.reservation_type, ''))) in ('rental', 'loaner')
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


alter function public.get_fleet_board_state(timestamptz, timestamptz) owner to postgres;
revoke all on function public.get_fleet_board_state(timestamptz, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.get_fleet_board_state(timestamptz, timestamptz) to postgres, authenticated, service_role;
