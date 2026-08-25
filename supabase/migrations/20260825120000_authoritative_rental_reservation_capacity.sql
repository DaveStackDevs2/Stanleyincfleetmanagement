-- Authoritative Rental Reservation model capacity. Data-free; do not seed limits.

alter table public.rental_model_limits drop constraint if exists ck_rental_model_limits_daily_limit;
alter table public.rental_model_limits add constraint ck_rental_model_limits_daily_limit
  check (daily_limit >= 0);
create unique index if not exists ux_rental_model_limits_normalized_vehicle_class
  on public.rental_model_limits(lower(btrim(vehicle_class)));

create or replace function public.get_rental_reservation_capacity_state(
  p_vehicle_class text,
  p_start_date timestamptz,
  p_expected_return_datetime timestamptz,
  p_exclude_reservation_id uuid default null
) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare
  v_user uuid;
  v_class text := nullif(btrim(p_vehicle_class), '');
  v_limit integer;
  v_days jsonb;
  v_available boolean;
  v_alternatives jsonb;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
  if coalesce(auth.jwt()->>'aal','') <> 'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
  if v_class is null then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
  if p_start_date is null or p_expected_return_datetime is null or p_expected_return_datetime <= p_start_date then
    raise exception 'Expected return must be after start' using errcode='22023';
  end if;

  select daily_limit into v_limit
  from public.rental_model_limits
  where lower(btrim(vehicle_class))=lower(v_class);

  with requested_days as (
    select d::date as local_date
    from generate_series(
      (p_start_date at time zone 'America/New_York')::date,
      ((p_expected_return_datetime - interval '1 microsecond') at time zone 'America/New_York')::date,
      interval '1 day'
    ) d
  ), counts as (
    select d.local_date, count(r.id)::integer as booked
    from requested_days d
    left join public.reservations r
      join public.transportation_events te on te.id=r.transportation_event_id and te.status='active'
      join public.rental_pricing_agreements a on a.reservation_id=r.id
        and a.transportation_event_id=r.transportation_event_id and a.is_active=true and a.pricing_started_at is null
      on lower(btrim(coalesce(r.reservation_type,'')))='rental'
      and lower(coalesce(r.status,''))<>'cancelled'
      and lower(btrim(coalesce(r.requested_model,'')))=lower(v_class)
      and (p_exclude_reservation_id is null or r.id<>p_exclude_reservation_id)
      and r.start_date < ((d.local_date + 1)::timestamp at time zone 'America/New_York')
      and r.expected_return_datetime > (d.local_date::timestamp at time zone 'America/New_York')
    group by d.local_date
  )
  select jsonb_agg(jsonb_build_object(
      'date',local_date,'booked_count',booked,'daily_limit',v_limit,
      'remaining_count',case when v_limit is null then null else greatest(v_limit-booked,0) end,
      'available',coalesce(booked<v_limit,false)
    ) order by local_date),
    coalesce(bool_and(booked<v_limit),false)
  into v_days,v_available from counts;

  with requested_days as (
    select d::date local_date from generate_series(
      (p_start_date at time zone 'America/New_York')::date,
      ((p_expected_return_datetime-interval '1 microsecond') at time zone 'America/New_York')::date,
      interval '1 day') d
  ), candidates as (
    select l.vehicle_class,l.daily_limit,rr.id rate_rule_id,rr.daily_rate,rr.weekly_rate,rr.monthly_rate,rr.sort_order
    from public.rental_model_limits l
    join public.rental_rate_rules rr on lower(btrim(rr.vehicle_class))=lower(btrim(l.vehicle_class))
      and rr.is_active=true and rr.effective_from<=clock_timestamp()
      and (rr.effective_to is null or rr.effective_to>clock_timestamp())
    where lower(btrim(l.vehicle_class))<>lower(v_class)
  ), availability as (
    select c.*, min(c.daily_limit-coalesce(x.booked,0))::integer minimum_remaining
    from candidates c cross join requested_days d
    left join lateral (
      select count(*)::integer booked
      from public.reservations r
      join public.transportation_events te on te.id=r.transportation_event_id and te.status='active'
      join public.rental_pricing_agreements a on a.reservation_id=r.id and a.transportation_event_id=r.transportation_event_id
        and a.is_active=true and a.pricing_started_at is null
      where lower(btrim(coalesce(r.reservation_type,'')))='rental'
        and lower(coalesce(r.status,''))<>'cancelled'
        and lower(btrim(coalesce(r.requested_model,'')))=lower(btrim(c.vehicle_class))
        and (p_exclude_reservation_id is null or r.id<>p_exclude_reservation_id)
        and r.start_date < ((d.local_date+1)::timestamp at time zone 'America/New_York')
        and r.expected_return_datetime > (d.local_date::timestamp at time zone 'America/New_York')
    ) x on true
    group by c.vehicle_class,c.daily_limit,c.rate_rule_id,c.daily_rate,c.weekly_rate,c.monthly_rate,c.sort_order
    having bool_and(coalesce(x.booked,0)<c.daily_limit)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'vehicle_class',vehicle_class,'daily_limit',daily_limit,'minimum_remaining',minimum_remaining,
    'rental_rate_rule_id',rate_rule_id,'daily_rate',daily_rate,'weekly_rate',weekly_rate,'monthly_rate',monthly_rate
  ) order by sort_order,vehicle_class),'[]'::jsonb) into v_alternatives from availability;

  return jsonb_build_object(
    'status',case when v_limit is null then 'not_configured' when v_available then 'available' else 'full' end,
    'vehicle_class',v_class,'requested_start',p_start_date,'requested_end',p_expected_return_datetime,
    'capacity_configured',v_limit is not null,'daily_limit',v_limit,'available',v_available,
    'days',coalesce(v_days,'[]'::jsonb),'alternatives',v_alternatives,
    'timezone','America/New_York','interval_semantics','[start,end)'
  );
end;$function$;

alter function public.get_rental_reservation_capacity_state(text,timestamptz,timestamptz,uuid) owner to postgres;
revoke all on function public.get_rental_reservation_capacity_state(text,timestamptz,timestamptz,uuid) from public,anon;
grant execute on function public.get_rental_reservation_capacity_state(text,timestamptz,timestamptz,uuid) to authenticated,service_role;

create or replace function public.get_admin_rental_reservation_capacity_state() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user uuid;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(
    select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage'
  ) then raise exception 'Reservation capacity administration access denied' using errcode='42501'; end if;
  return jsonb_build_object('status','admin_rental_reservation_capacity_ready','models',(
    select coalesce(jsonb_agg(jsonb_build_object('vehicle_class',rr.vehicle_class,'daily_limit',l.daily_limit,
      'configured',l.id is not null) order by rr.sort_order,rr.vehicle_class),'[]'::jsonb)
    from public.rental_rate_rules rr left join public.rental_model_limits l
      on lower(btrim(l.vehicle_class))=lower(btrim(rr.vehicle_class))
    where rr.is_active=true and rr.effective_from<=clock_timestamp() and (rr.effective_to is null or rr.effective_to>clock_timestamp())
  ));
end;$function$;

create or replace function public.upsert_admin_rental_reservation_capacity_state(p_vehicle_class text,p_daily_limit integer) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_class text;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Reservation capacity administration access denied' using errcode='42501'; end if;
  if p_daily_limit is null or p_daily_limit<0 then raise exception 'Reservation capacity must be an integer zero or greater' using errcode='22023'; end if;
  select vehicle_class into v_class from public.rental_rate_rules where lower(btrim(vehicle_class))=lower(btrim(p_vehicle_class)) and is_active=true and effective_from<=clock_timestamp() and (effective_to is null or effective_to>clock_timestamp()) order by effective_from desc limit 1;
  if v_class is null then raise exception 'Active Rental rate card not found' using errcode='P0002'; end if;
  insert into public.rental_model_limits(vehicle_class,daily_limit) values(v_class,p_daily_limit)
  on conflict(vehicle_class) do update set daily_limit=excluded.daily_limit;
  return jsonb_build_object('status','admin_rental_reservation_capacity_saved','vehicle_class',v_class,'daily_limit',p_daily_limit);
end;$function$;

create or replace function public.remove_admin_rental_reservation_capacity_state(p_vehicle_class text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_count integer;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Reservation capacity administration access denied' using errcode='42501'; end if;
  delete from public.rental_model_limits where lower(btrim(vehicle_class))=lower(btrim(p_vehicle_class)); get diagnostics v_count=row_count;
  return jsonb_build_object('status','admin_rental_reservation_capacity_removed','vehicle_class',btrim(p_vehicle_class),'removed',v_count=1);
end;$function$;

alter function public.get_admin_rental_reservation_capacity_state() owner to postgres;
alter function public.upsert_admin_rental_reservation_capacity_state(text,integer) owner to postgres;
alter function public.remove_admin_rental_reservation_capacity_state(text) owner to postgres;
revoke all on function public.get_admin_rental_reservation_capacity_state() from public,anon;
revoke all on function public.upsert_admin_rental_reservation_capacity_state(text,integer) from public,anon;
revoke all on function public.remove_admin_rental_reservation_capacity_state(text) from public,anon;
grant execute on function public.get_admin_rental_reservation_capacity_state() to authenticated,service_role;
grant execute on function public.upsert_admin_rental_reservation_capacity_state(text,integer) to authenticated,service_role;
grant execute on function public.remove_admin_rental_reservation_capacity_state(text) to authenticated,service_role;

-- Preserve the established intake/edit engines and put one capacity gate in front of each Rental write.
alter function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text)
  rename to create_reservation_with_pricing_agreement_without_capacity_state;
alter function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text)
  rename to convert_quote_to_reservation_with_pricing_agreement_without_capacity_state;
alter function public.update_precheckin_reservation_state(uuid,timestamptz,timestamptz,text,text,text)
  rename to update_precheckin_reservation_without_capacity_state;

create function public.create_reservation_with_pricing_agreement_state(p_customer_id uuid,p_vehicle_class text,p_start_date timestamptz,p_expected_return_datetime timestamptz,p_reservation_type text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_service_advisor text default null,p_ro_number text default null,p_notes text default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$ declare v_capacity jsonb; v_user uuid; begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management access denied' using errcode='42501'; end if;
  if lower(btrim(coalesce(p_reservation_type,'')))='rental' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(btrim(p_vehicle_class)),0));
    v_capacity:=public.get_rental_reservation_capacity_state(p_vehicle_class,p_start_date,p_expected_return_datetime,null);
    if not coalesce((v_capacity->>'available')::boolean,false) then raise exception 'Rental reservation capacity unavailable: %',v_capacity->>'status' using errcode='P0001',detail=v_capacity::text; end if;
  end if;
  return public.create_reservation_with_pricing_agreement_without_capacity_state(p_customer_id,p_vehicle_class,p_start_date,p_expected_return_datetime,p_reservation_type,p_pay_type_rule_id,p_initial_rate_plan,p_service_advisor,p_ro_number,p_notes);
end;$function$;

create function public.convert_quote_to_reservation_with_pricing_agreement_state(p_quote_id uuid,p_service_advisor text default null,p_ro_number text default null,p_notes text default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$ declare q public.quotes%rowtype; v_capacity jsonb; v_user uuid; begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management access denied' using errcode='42501'; end if;
  select * into q from public.quotes where id=p_quote_id;
  if lower(btrim(coalesce(q.reservation_type,'')))='rental' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(btrim(q.vehicle_class)),0));
    v_capacity:=public.get_rental_reservation_capacity_state(q.vehicle_class,q.start_date,q.expected_return_datetime,null);
    if not coalesce((v_capacity->>'available')::boolean,false) then raise exception 'Rental reservation capacity unavailable: %',v_capacity->>'status' using errcode='P0001',detail=v_capacity::text; end if;
  end if;
  return public.convert_quote_to_reservation_with_pricing_agreement_without_capacity_state(p_quote_id,p_service_advisor,p_ro_number,p_notes);
end;$function$;

create function public.update_precheckin_reservation_state(p_reservation_id uuid,p_start_date timestamptz,p_expected_return_datetime timestamptz,p_service_advisor text default null,p_ro_number text default null,p_notes text default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$ declare r public.reservations%rowtype; v_capacity jsonb; v_user uuid; begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management access denied' using errcode='42501'; end if;
  select * into r from public.reservations where id=p_reservation_id;
  if lower(btrim(coalesce(r.reservation_type,'')))='rental'
     and (r.start_date is distinct from p_start_date or r.expected_return_datetime is distinct from p_expected_return_datetime) then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(btrim(r.requested_model)),0));
    v_capacity:=public.get_rental_reservation_capacity_state(r.requested_model,p_start_date,p_expected_return_datetime,p_reservation_id);
    if not coalesce((v_capacity->>'available')::boolean,false) then raise exception 'Rental reservation capacity unavailable: %',v_capacity->>'status' using errcode='P0001',detail=v_capacity::text; end if;
  end if;
  return public.update_precheckin_reservation_without_capacity_state(p_reservation_id,p_start_date,p_expected_return_datetime,p_service_advisor,p_ro_number,p_notes);
end;$function$;

alter function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) owner to postgres;
alter function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) owner to postgres;
alter function public.update_precheckin_reservation_state(uuid,timestamptz,timestamptz,text,text,text) owner to postgres;
revoke all on function public.create_reservation_with_pricing_agreement_without_capacity_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.convert_quote_to_reservation_with_pricing_agreement_without_capacity_state(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.update_precheckin_reservation_without_capacity_state(uuid,timestamptz,timestamptz,text,text,text) from public,anon,authenticated;
revoke all on function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) from public,anon;
revoke all on function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) from public,anon;
revoke all on function public.update_precheckin_reservation_state(uuid,timestamptz,timestamptz,text,text,text) from public,anon;
grant execute on function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.update_precheckin_reservation_state(uuid,timestamptz,timestamptz,text,text,text) to authenticated,service_role;

-- Fleet Board consumes authoritative per-day state rather than asking React to recount.
create or replace function public.get_fleet_board_capacity_state(p_range_start timestamptz,p_range_end timestamptz) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null then raise exception 'Fleet Board access denied' using errcode='42501'; end if;
  if p_range_start is null or p_range_end<=p_range_start or p_range_end-p_range_start>interval '32 days' then raise exception 'Invalid Fleet Board date range' using errcode='22023'; end if;
  return (select coalesce(jsonb_agg(public.get_rental_reservation_capacity_state(l.vehicle_class,p_range_start,p_range_end,null) order by l.vehicle_class),'[]'::jsonb) from public.rental_model_limits l);
end;$function$;
alter function public.get_fleet_board_capacity_state(timestamptz,timestamptz) owner to postgres;
revoke all on function public.get_fleet_board_capacity_state(timestamptz,timestamptz) from public,anon;
grant execute on function public.get_fleet_board_capacity_state(timestamptz,timestamptz) to authenticated,service_role;
