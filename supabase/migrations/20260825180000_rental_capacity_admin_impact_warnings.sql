-- Fixed Rental capacity administration and derived future impact warnings.
-- Data-free repository migration; intentionally does not seed capacity.

create or replace function public.evaluate_admin_rental_reservation_capacity_impact(
  p_vehicle_class text,
  p_daily_limit integer
) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare
  v_class text := nullif(btrim(p_vehicle_class),'');
  v_effective_limit integer := coalesce(p_daily_limit,0);
  v_today date := (clock_timestamp() at time zone 'America/New_York')::date;
  v_days jsonb;
  v_reservations jsonb;
  v_quotes jsonb;
begin
  if v_class is null then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
  if p_daily_limit is not null and p_daily_limit<0 then raise exception 'Reservation capacity must be an integer zero or greater' using errcode='22023'; end if;

  with reservation_days as (
    select d::date local_date,count(distinct r.id)::integer reservation_count
    from public.reservations r
    join public.transportation_events te on te.id=r.transportation_event_id and te.status='active'
    join public.rental_pricing_agreements a on a.reservation_id=r.id
      and a.transportation_event_id=r.transportation_event_id and a.is_active=true and a.pricing_started_at is null
    cross join lateral generate_series(
      greatest((r.start_date at time zone 'America/New_York')::date,v_today),
      ((r.expected_return_datetime-interval '1 microsecond') at time zone 'America/New_York')::date,
      interval '1 day') d
    where lower(btrim(coalesce(r.reservation_type,'')))='rental'
      and lower(coalesce(r.status,''))<>'cancelled'
      and lower(btrim(coalesce(r.requested_model,'')))=lower(v_class)
      and r.expected_return_datetime>(v_today::timestamp at time zone 'America/New_York')
    group by d::date
  ), quote_days as (
    select d::date local_date,count(distinct q.id)::integer quote_count
    from public.quotes q
    join public.rental_pricing_agreements a on a.quote_id=q.id and a.origin_type='quote'
      and a.reservation_id is null and a.is_active=true
    join public.transportation_events te on te.id=a.transportation_event_id and te.status='active'
    cross join lateral generate_series(
      greatest((q.start_date at time zone 'America/New_York')::date,v_today),
      ((q.expected_return_datetime-interval '1 microsecond') at time zone 'America/New_York')::date,
      interval '1 day') d
    where lower(btrim(coalesce(q.reservation_type,'')))='rental'
      and q.is_active=true and lower(coalesce(q.status,''))='active'
      and q.converted_to_reservation_id is null
      and lower(btrim(coalesce(a.vehicle_class,q.vehicle_class,'')))=lower(v_class)
      and q.expected_return_datetime>(v_today::timestamp at time zone 'America/New_York')
    group by d::date
  ), days as (
    select coalesce(r.local_date,q.local_date) local_date,coalesce(r.reservation_count,0) reservation_count,
      coalesce(q.quote_count,0) quote_count
    from reservation_days r full join quote_days q using(local_date)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'date',local_date,'capacity',v_effective_limit,'capacity_configured',p_daily_limit is not null,
    'reservation_count',reservation_count,'reservation_overage',greatest(reservation_count-v_effective_limit,0),
    'hard_reservation_conflict',reservation_count>v_effective_limit,
    'active_quote_count',quote_count,'combined_count',reservation_count+quote_count,
    'quote_pressure_overage',greatest(reservation_count+quote_count-v_effective_limit,0),
    'at_risk_quote_pressure',quote_count>0 and reservation_count+quote_count>v_effective_limit
  ) order by local_date) filter(where reservation_count>v_effective_limit or (quote_count>0 and reservation_count+quote_count>v_effective_limit)),'[]'::jsonb)
  into v_days from days;

  with conflict_days as (
    select (x->>'date')::date local_date from jsonb_array_elements(v_days) x where (x->>'hard_reservation_conflict')::boolean
  ), affected as (
    select r.id,r.customer_id,c.name customer_name,r.requested_model,r.start_date,r.expected_return_datetime,r.status,
      jsonb_agg(cd.local_date order by cd.local_date) conflict_dates
    from public.reservations r
    join public.transportation_events te on te.id=r.transportation_event_id and te.status='active'
    join public.rental_pricing_agreements a on a.reservation_id=r.id and a.transportation_event_id=r.transportation_event_id
      and a.is_active=true and a.pricing_started_at is null
    left join public.customers c on c.id=r.customer_id
    join conflict_days cd on r.start_date<((cd.local_date+1)::timestamp at time zone 'America/New_York')
      and r.expected_return_datetime>(cd.local_date::timestamp at time zone 'America/New_York')
    where lower(btrim(coalesce(r.reservation_type,'')))='rental' and lower(coalesce(r.status,''))<>'cancelled'
      and lower(btrim(coalesce(r.requested_model,'')))=lower(v_class)
    group by r.id,r.customer_id,c.name,r.requested_model,r.start_date,r.expected_return_datetime,r.status
  ) select coalesce(jsonb_agg(jsonb_build_object('reservation_id',id,'customer_id',customer_id,'customer_name',customer_name,
      'vehicle_class',requested_model,'start_date',start_date,'expected_return_datetime',expected_return_datetime,
      'status',status,'conflict_dates',conflict_dates) order by start_date,id),'[]'::jsonb)
    into v_reservations from affected;

  with risk_days as (
    select (x->>'date')::date local_date from jsonb_array_elements(v_days) x where (x->>'at_risk_quote_pressure')::boolean
  ), affected as (
    select q.id,q.customer_id,c.name customer_name,coalesce(a.vehicle_class,q.vehicle_class) vehicle_class,
      q.start_date,q.expected_return_datetime,q.status,jsonb_agg(rd.local_date order by rd.local_date) risk_dates
    from public.quotes q
    join public.rental_pricing_agreements a on a.quote_id=q.id and a.origin_type='quote' and a.reservation_id is null and a.is_active=true
    join public.transportation_events te on te.id=a.transportation_event_id and te.status='active'
    left join public.customers c on c.id=q.customer_id
    join risk_days rd on q.start_date<((rd.local_date+1)::timestamp at time zone 'America/New_York')
      and q.expected_return_datetime>(rd.local_date::timestamp at time zone 'America/New_York')
    where lower(btrim(coalesce(q.reservation_type,'')))='rental' and q.is_active=true
      and lower(coalesce(q.status,''))='active' and q.converted_to_reservation_id is null
      and lower(btrim(coalesce(a.vehicle_class,q.vehicle_class,'')))=lower(v_class)
    group by q.id,q.customer_id,c.name,a.vehicle_class,q.vehicle_class,q.start_date,q.expected_return_datetime,q.status
  ) select coalesce(jsonb_agg(jsonb_build_object('quote_id',id,'customer_id',customer_id,'customer_name',customer_name,
      'vehicle_class',vehicle_class,'start_date',start_date,'expected_return_datetime',expected_return_datetime,
      'status',status,'risk_dates',risk_dates) order by start_date,id),'[]'::jsonb)
    into v_quotes from affected;

  return jsonb_build_object('vehicle_class',v_class,'daily_limit',p_daily_limit,'effective_capacity',v_effective_limit,
    'capacity_configured',p_daily_limit is not null,'timezone','America/New_York','interval_semantics','[start,end)',
    'days',v_days,'hard_reservation_conflicts',v_reservations,'at_risk_quotes',v_quotes);
end;$function$;

create or replace function public.get_admin_rental_reservation_capacity_state() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user uuid;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(
    select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage'
  ) then raise exception 'Reservation capacity administration access denied' using errcode='42501'; end if;
  return jsonb_build_object('status','admin_rental_reservation_capacity_ready','models',(
    with active_rates as (
      select distinct on(lower(btrim(vehicle_class))) vehicle_class,sort_order
      from public.rental_rate_rules where is_active=true and effective_from<=clock_timestamp()
        and (effective_to is null or effective_to>clock_timestamp())
      order by lower(btrim(vehicle_class)),effective_from desc,id
    ), models as (
      select coalesce(l.vehicle_class,r.vehicle_class) vehicle_class,l.daily_limit,l.id is not null configured,
        r.vehicle_class is not null has_active_rate_card,coalesce(r.sort_order,2147483647) sort_order
      from public.rental_model_limits l full join active_rates r
        on lower(btrim(l.vehicle_class))=lower(btrim(r.vehicle_class))
    ) select coalesce(jsonb_agg(jsonb_build_object('vehicle_class',vehicle_class,'daily_limit',daily_limit,
      'configured',configured,'has_active_rate_card',has_active_rate_card,
      'impact',public.evaluate_admin_rental_reservation_capacity_impact(vehicle_class,daily_limit))
      order by sort_order,lower(vehicle_class)),'[]'::jsonb) from models));
end;$function$;

create or replace function public.upsert_admin_rental_reservation_capacity_state(p_vehicle_class text,p_daily_limit integer) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_class text:=nullif(btrim(p_vehicle_class),''); v_count integer; v_impact jsonb;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Reservation capacity administration access denied' using errcode='42501'; end if;
  if v_class is null then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
  if p_daily_limit is null or p_daily_limit<0 then raise exception 'Reservation capacity must be an integer zero or greater' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(v_class),0));
  select vehicle_class into v_class from public.rental_model_limits where lower(btrim(vehicle_class))=lower(v_class);
  if v_class is null then
    v_class:=btrim(p_vehicle_class);
    select vehicle_class into v_class from public.rental_rate_rules where lower(btrim(vehicle_class))=lower(v_class)
      and is_active=true and effective_from<=clock_timestamp() and (effective_to is null or effective_to>clock_timestamp())
      order by effective_from desc,id limit 1;
    v_class:=coalesce(v_class,btrim(p_vehicle_class));
  end if;
  update public.rental_model_limits set daily_limit=p_daily_limit where lower(btrim(vehicle_class))=lower(btrim(v_class));
  get diagnostics v_count=row_count;
  if v_count=0 then insert into public.rental_model_limits(vehicle_class,daily_limit) values(v_class,p_daily_limit); end if;
  v_impact:=public.evaluate_admin_rental_reservation_capacity_impact(v_class,p_daily_limit);
  return jsonb_build_object('status','admin_rental_reservation_capacity_saved','vehicle_class',v_class,'daily_limit',p_daily_limit,'impact',v_impact);
end;$function$;

create or replace function public.remove_admin_rental_reservation_capacity_state(p_vehicle_class text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_class text:=nullif(btrim(p_vehicle_class),''); v_count integer; v_impact jsonb;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Reservation capacity administration access denied' using errcode='42501'; end if;
  if v_class is null then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(v_class),0));
  select vehicle_class into v_class from public.rental_model_limits where lower(btrim(vehicle_class))=lower(v_class);
  if v_class is null then v_class:=btrim(p_vehicle_class); end if;
  delete from public.rental_model_limits where lower(btrim(vehicle_class))=lower(v_class); get diagnostics v_count=row_count;
  v_impact:=public.evaluate_admin_rental_reservation_capacity_impact(v_class,null);
  return jsonb_build_object('status','admin_rental_reservation_capacity_removed','vehicle_class',v_class,'removed',v_count=1,'impact',v_impact);
end;$function$;

alter function public.evaluate_admin_rental_reservation_capacity_impact(text,integer) owner to postgres;
alter function public.get_admin_rental_reservation_capacity_state() owner to postgres;
alter function public.upsert_admin_rental_reservation_capacity_state(text,integer) owner to postgres;
alter function public.remove_admin_rental_reservation_capacity_state(text) owner to postgres;
revoke all on function public.evaluate_admin_rental_reservation_capacity_impact(text,integer) from public,anon,authenticated;
grant execute on function public.evaluate_admin_rental_reservation_capacity_impact(text,integer) to service_role;
revoke all on function public.get_admin_rental_reservation_capacity_state() from public,anon;
revoke all on function public.upsert_admin_rental_reservation_capacity_state(text,integer) from public,anon;
revoke all on function public.remove_admin_rental_reservation_capacity_state(text) from public,anon;
grant execute on function public.get_admin_rental_reservation_capacity_state() to authenticated,service_role;
grant execute on function public.upsert_admin_rental_reservation_capacity_state(text,integer) to authenticated,service_role;
grant execute on function public.remove_admin_rental_reservation_capacity_state(text) to authenticated,service_role;
