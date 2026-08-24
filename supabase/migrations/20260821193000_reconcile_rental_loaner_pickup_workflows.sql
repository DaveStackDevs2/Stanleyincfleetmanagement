-- Reconcile the shared Pickup engine's Rental and Loaner contracts. Data-free.

create or replace function public.start_reservation_vehicle_use_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz)
returns jsonb language plpgsql as $function$
declare v_reservation public.reservations%rowtype; v_vehicle_fleet_type text; v_reservation_type text; v_vehicle_type text; v_start_result jsonb;
begin
 select * into v_reservation from public.reservations where id=p_reservation_id for update;
 if not found then raise exception 'Reservation % does not exist',p_reservation_id using errcode='P0002'; end if;
 select fleet_type into v_vehicle_fleet_type from public.vehicles where id=p_vehicle_id;
 if not found then raise exception 'Vehicle % does not exist',p_vehicle_id using errcode='P0002'; end if;
 v_reservation_type:=nullif(lower(btrim(v_reservation.reservation_type)),'');
 v_vehicle_type:=nullif(lower(btrim(v_vehicle_fleet_type)),'');
 if v_reservation_type not in ('rental','loaner') or v_vehicle_type not in ('rental','loaner') or
    (v_reservation_type='rental' and v_vehicle_type<>'rental') then
  raise exception 'Vehicle fleet type % is not eligible for reservation type %',v_vehicle_fleet_type,v_reservation.reservation_type using errcode='22023';
 end if;
 if v_reservation_type='loaner' and nullif(btrim(v_reservation.ro_number),'') is null then
  raise exception 'Loaner pickup requires a repair-order number before vehicle assignment' using errcode='22023';
 end if;
 if p_actual_out_at is null then raise exception 'actual_out_at cannot be null' using errcode='22023'; end if;
 if p_actual_out_at<v_reservation.start_date then raise exception 'actual_out_at % is before reservation start_date %',p_actual_out_at,v_reservation.start_date using errcode='22023'; end if;
 v_start_result:=public.start_vehicle_use_state(v_reservation.transportation_event_id,p_vehicle_id,p_actual_out_at);
 update public.reservations set vehicle_id=p_vehicle_id where id=p_reservation_id;
 return jsonb_build_object('status','reservation_vehicle_use_started','reservation_id',p_reservation_id,'transportation_event_id',v_reservation.transportation_event_id,'vehicle_id',p_vehicle_id,'actual_out_at',p_actual_out_at,'continuity_result',v_start_result);
end;$function$;
alter function public.start_reservation_vehicle_use_state(uuid,uuid,timestamptz) owner to postgres;
revoke all on function public.start_reservation_vehicle_use_state(uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.start_reservation_vehicle_use_state(uuid,uuid,timestamptz) to postgres,service_role;

create or replace view public.v_reservation_vehicle_candidates with (security_invoker=true) as
select r.id as reservation_id,r.transportation_event_id as reservation_transportation_event_id,r.start_date as reservation_start_at,
 r.expected_return_datetime as reservation_end_at,r.requested_model,r.reservation_type,r.status as reservation_status,r.notes as reservation_notes,
 v.id as vehicle_id,v.vin,v.stock_number,v.model as vehicle_model,v.fleet_type,v.status as vehicle_status,v.recon_status,v.location,
 c.transportation_event_id as source_transportation_event_id,te.expected_return_at as expected_return_snapshot,
 case when c.vehicle_event_id is not null then 'pending_return'::text when v.status='available'::text then 'ready'::text else 'unavailable'::text end as candidate_state
from public.reservations r
JOIN public.vehicles AS v
  ON v.model = r.requested_model
 AND v.is_retired = false
 and ((lower(btrim(r.reservation_type))='rental' and lower(btrim(v.fleet_type))='rental') or
      (lower(btrim(r.reservation_type))='loaner' and lower(btrim(v.fleet_type)) in ('loaner','rental')))
left join public.v_current_vehicle_continuity c on c.vehicle_id=v.id
left join public.transportation_events te on te.id=c.transportation_event_id
where r.status is distinct from 'cancelled'::text;
alter view public.v_reservation_vehicle_candidates owner to postgres;

create or replace function public.get_pricing_agreement_pickup_state(p_reference_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_vin_lock_lead_days integer:=0; v_items jsonb;
begin
 if p_reference_at is null then raise exception 'Reference timestamp is required' using errcode='22023'; end if;
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null then raise exception 'An active application user is required' using errcode='42501'; end if;
  if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication is required' using errcode='42501'; end if;
  if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing-agreement permission is required' using errcode='42501'; end if;
 select coalesce((setting_value #>> '{}')::integer,0) into v_vin_lock_lead_days from public.admin_settings where setting_key='reservation_vin_lock_lead_days';
 v_vin_lock_lead_days:=coalesce(v_vin_lock_lead_days,0);
 select coalesce(jsonb_agg(jsonb_build_object(
   'reservation_id',r.id,'transportation_event_id',r.transportation_event_id,'reservation_status',r.status,
   'reservation_type',r.reservation_type,'start_date',r.start_date,'expected_return_datetime',r.expected_return_datetime,
   'service_advisor',r.service_advisor,'ro_number',r.ro_number,'notes',r.notes,'vehicle_class',a.vehicle_class,'assigned_vehicle_id',r.vehicle_id,
   'customer',jsonb_build_object('customer_id',c.id,'tekion_customer_number',c.tekion_customer_number,'name',c.name,'phone',c.phone,'email',c.email),
   'pricing_agreement',jsonb_build_object('pricing_agreement_id',a.id,'origin_type',a.origin_type,
     'pay_type_rule_id',a.pay_type_rule_id,'pay_type',p.pay_type,'initial_rate_plan',a.initial_rate_plan,'current_rate_plan',a.current_rate_plan,
     'daily_rate',a.daily_rate_snapshot::text,'weekly_rate',a.weekly_rate_snapshot::text,'monthly_rate',a.monthly_rate_snapshot::text,'pricing_started_at',a.pricing_started_at),
   'vin_lock',jsonb_build_object('lead_days',v_vin_lock_lead_days,'lock_window_starts_at',r.start_date-make_interval(days=>v_vin_lock_lead_days),
     'is_in_lock_window',p_reference_at >= r.start_date-make_interval(days=>v_vin_lock_lead_days)),
   'vehicle_candidates',coalesce((select jsonb_agg(jsonb_build_object(
        'vehicle_id',vc.vehicle_id,'vin',vc.vin,'stock_number',vc.stock_number,'model',vc.vehicle_model,
        'fleet_type',vc.fleet_type,'vehicle_status',vc.vehicle_status,'recon_status',vc.recon_status,'location',vc.location,
        'source_transportation_event_id',vc.source_transportation_event_id,'expected_return_snapshot',vc.expected_return_snapshot,
        'candidate_state',vc.candidate_state)
      order by case vc.candidate_state when 'ready' then 1 when 'pending_return' then 2 else 3 end,
        case when lower(btrim(r.reservation_type))='loaner' and lower(btrim(vc.fleet_type))='loaner' then 1 else 2 end,
        vc.expected_return_snapshot asc nulls last,vc.stock_number asc nulls last,vc.vin asc nulls last)
      from public.v_reservation_vehicle_candidates vc where vc.reservation_id=r.id),'[]'::jsonb)) order by r.start_date,r.id),'[]'::jsonb)
 into v_items
 from public.reservations r
 join public.rental_pricing_agreements a on a.reservation_id=r.id and a.transportation_event_id=r.transportation_event_id and a.is_active=true
 join public.transportation_events te on te.id=r.transportation_event_id and te.status='active'
 join public.customers c on c.id=r.customer_id
 join public.pay_type_rules p on p.id=a.pay_type_rule_id
 where r.status is distinct from 'cancelled' and r.actual_return_datetime is null and a.pricing_started_at is null;
 return jsonb_build_object('status','pricing_agreement_pickup_ready','reference_at',p_reference_at,'vin_lock_lead_days',v_vin_lock_lead_days,'items',v_items);
end;$function$;

alter function public.get_pricing_agreement_pickup_state(timestamptz) owner to postgres;
revoke all on function public.get_pricing_agreement_pickup_state(timestamptz) from public,anon;
grant execute on function public.get_pricing_agreement_pickup_state(timestamptz) to postgres,authenticated,service_role;


create or replace function public.activate_pricing_agreement_pickup_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz,p_start_mileage integer default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_user uuid; v_agreement public.rental_pricing_agreements%rowtype; v_reservation public.reservations%rowtype; v_vehicle public.vehicles%rowtype;
 v_pay_type public.pay_type_rules%rowtype; v_started jsonb; v_billing_result jsonb; v_vehicle_event uuid; v_contract_period uuid; v_line_id uuid; v_preview jsonb; v_rate_amount numeric;
 v_current_vehicle_id uuid; v_existing_line uuid; v_tax_sync jsonb; v_tax_count integer; v_tax_sum numeric; v_payment jsonb; v_reservation_type text;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null then raise exception 'An active application user is required' using errcode='42501'; end if;
  if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication is required' using errcode='42501'; end if;
  if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.case_start') then
   raise exception 'Billing case-start permission is required' using errcode='42501';
  end if;
  if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then
   raise exception 'Pricing-agreement permission is required' using errcode='42501';
  end if;
  if p_reservation_id is null or p_vehicle_id is null or p_actual_out_at is null then raise exception 'Reservation, vehicle, and actual-out time are required' using errcode='22023'; end if;
  if p_start_mileage is not null and p_start_mileage<0 then raise exception 'Start mileage must be nonnegative' using errcode='22023'; end if;
  select * into v_reservation from public.reservations where id=p_reservation_id for update;
  if not found then raise exception 'Reservation was not found' using errcode='P0002'; end if;
  if lower(coalesce(v_reservation.status,''))='cancelled' or v_reservation.actual_return_datetime is not null then raise exception 'Reservation is not eligible for pickup' using errcode='P0001'; end if;
  v_reservation_type:=lower(btrim(coalesce(v_reservation.reservation_type,'')));
  if v_reservation_type not in ('rental','loaner') then raise exception 'Unsupported reservation type for pickup' using errcode='22023'; end if;
  if p_actual_out_at<v_reservation.start_date then raise exception 'Actual-out time cannot precede reservation start' using errcode='22023'; end if;
  select * into v_agreement from public.rental_pricing_agreements where reservation_id=v_reservation.id and transportation_event_id=v_reservation.transportation_event_id and is_active=true for update;
  if not found then raise exception 'Active pricing agreement was not found' using errcode='P0002'; end if;
  if v_agreement.current_rate_plan<>'daily' then raise exception 'Weekly/monthly pickup billing is not implemented yet' using errcode='P0001'; end if;
 v_rate_amount:=v_agreement.daily_rate_snapshot;
  if v_rate_amount is null or v_rate_amount<0 or v_rate_amount::text in ('NaN','Infinity','-Infinity') then raise exception 'Pricing agreement daily-rate snapshot is invalid' using errcode='P0001'; end if;
 select p.* into v_pay_type from public.pay_type_rules p where p.id=v_agreement.pay_type_rule_id;
  if not found then raise exception 'Pricing-agreement pay type was not found' using errcode='P0002'; end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and is_retired=false for update;
  if not found then raise exception 'Pickup vehicle was not found or is retired' using errcode='P0002'; end if;
  IF v_vehicle.status IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION
        'Selected vehicle is not available for pickup'
        USING ERRCODE = 'P0001';
  END IF;
  if lower(btrim(v_vehicle.model))<>lower(btrim(v_agreement.vehicle_class)) then raise exception 'Pickup vehicle does not match the pricing-agreement vehicle class' using errcode='22023'; end if;
  if v_reservation.vehicle_id is not null and v_reservation.vehicle_id is distinct from p_vehicle_id then raise exception 'Reservation is assigned to a different vehicle' using errcode='P0001'; end if;
 select c.vehicle_id into v_current_vehicle_id
 from public.v_current_vehicle_continuity c where c.transportation_event_id=v_reservation.transportation_event_id limit 1;
 select bl.id into v_existing_line from public.billing_lines bl where bl.transportation_event_id=v_reservation.transportation_event_id
   and bl.parent_billing_line_id is null and bl.is_open=true
   order by bl.start_time desc nulls last,bl.created_at desc,bl.id desc limit 1;
 if v_agreement.pricing_started_at is not null then
  if v_current_vehicle_id=p_vehicle_id and v_existing_line is not null then
   if v_reservation_type='rental' then
    v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime);
    v_payment:=public.get_rental_payment_state(v_reservation.transportation_event_id);
   else
    v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,clock_timestamp());
    v_payment:=null;
   end if;
   if v_preview->>'status'<>'billing_preview_ready' then raise exception 'Activated pickup could not be loaded by Billing' using errcode='P0001'; end if;
   return jsonb_build_object('status','pricing_agreement_pickup_already_active','reservation_type',v_reservation_type,'ro_number',v_reservation.ro_number,'reservation_id',p_reservation_id,'transportation_event_id',v_reservation.transportation_event_id,'pricing_agreement_id',v_agreement.id,'vehicle_id',p_vehicle_id,'billing_line_id',v_existing_line,'pricing_started_at',v_agreement.pricing_started_at,'billing_preview',v_preview,'rental_payment_state',v_payment);
  end if;
   raise exception 'Existing pickup state is inconsistent' using errcode='P0001';
 end if;
 if v_current_vehicle_id is not null or v_existing_line is not null then raise exception 'Pre-pickup case already has active continuity or billing' using errcode='P0001'; end if;
  if exists(select 1 from public.v_current_vehicle_continuity c where c.vehicle_id=p_vehicle_id) then raise exception 'Selected vehicle is currently assigned to another case' using errcode='P0001'; end if;
 v_started:=public.start_reservation_vehicle_use_state(v_reservation.id,p_vehicle_id,p_actual_out_at);
 begin v_vehicle_event:=(v_started->'continuity_result'->>'vehicle_event_id')::uuid; v_contract_period:=(v_started->'continuity_result'->>'contract_period_id')::uuid;
 exception when invalid_text_representation then raise exception 'Vehicle-start engine returned malformed identifiers' using errcode='P0001'; end;
 if v_vehicle_event is null or v_contract_period is null then raise exception 'Vehicle-start engine did not return required continuity identifiers' using errcode='P0001'; end if;
 update public.reservations set status='active',start_mileage=coalesce(p_start_mileage,start_mileage) where id=v_reservation.id;
 update public.vehicle_events set created_by=v_user,updated_by=v_user where id=v_vehicle_event;
 update public.contract_periods set created_by=v_user,updated_by=v_user where id=v_contract_period;
 v_billing_result:=public.activate_case_billing_state(v_reservation.id,v_rate_amount,null,null,null,'initial_assignment','pricing_agreement_daily',v_pay_type.pay_type);
 if v_billing_result->>'status'<>'case_billing_activated' then raise exception 'Billing engine did not activate the reservation billing case'; end if;
 if v_billing_result->'billing_result'->>'status'<>'reservation_billing_line_created' then raise exception 'Reservation billing engine did not create the billing line'; end if;
 if v_billing_result->'billing_result'->'billing_result'->>'status'<>'parent_billing_line_created' then raise exception 'Billing engine did not create the initial billing line'; end if;
 begin v_line_id:=(v_billing_result->'billing_result'->'billing_result'->>'parent_billing_line_id')::uuid; exception when invalid_text_representation then raise exception 'Billing engine returned a malformed billing-line identifier'; end;
 if v_line_id is null then raise exception 'Billing engine did not return a billing-line identifier'; end if;
 update public.billing_lines set pricing_agreement_id=v_agreement.id,rate_plan_snapshot='daily',rate_amount_snapshot=v_rate_amount,default_daily_rate_snapshot=v_agreement.daily_rate_snapshot where id=v_line_id;
 if not exists(select 1 from public.billing_lines line where line.id=v_line_id and line.start_time is not distinct from v_reservation.start_date) then raise exception 'Billing engine did not use the reservation scheduled start'; end if;
 update public.rental_pricing_agreements set pricing_started_at=v_reservation.start_date,updated_by=v_user,updated_at=clock_timestamp() where id=v_agreement.id returning * into v_agreement;
 if v_reservation_type='rental' then
  v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime);
  if v_preview->>'status'='billing_preview_ready' then
   update public.billing_lines set amount=(v_preview->>'subtotal')::numeric,tax_amount=(v_preview->>'tax_amount')::numeric,end_time=v_reservation.expected_return_datetime where id=v_line_id;
   v_tax_sync:=public.ensure_tax_child_line_state(v_line_id);
   select count(*),sum(amount) into v_tax_count,v_tax_sum from public.billing_lines where parent_billing_line_id=v_line_id and line_type='tax';
   if (((v_preview->>'tax_amount')::numeric>0 and (v_tax_count<>1 or v_tax_sum is distinct from (v_preview->>'tax_amount')::numeric)) or ((v_preview->>'tax_amount')::numeric=0 and v_tax_count<>0)) then raise exception 'Pickup tax child does not match authoritative tax'; end if;
   v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime);
  end if;
  v_payment:=public.get_rental_payment_state(v_reservation.transportation_event_id);
 else
  v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,clock_timestamp());
  v_payment:=null;
 end if;
 if v_preview->>'status'<>'billing_preview_ready' then raise exception 'Activated pickup could not be loaded by Billing' using errcode='P0001'; end if;
 return jsonb_build_object('rental_payment_state',v_payment,'status','pricing_agreement_pickup_activated','reservation_type',v_reservation_type,'ro_number',v_reservation.ro_number,'reservation_id',v_reservation.id,'transportation_event_id',v_reservation.transportation_event_id,'vehicle_id',p_vehicle_id,'vehicle_event_id',v_vehicle_event,'contract_period_id',v_contract_period,'pricing_agreement_id',v_agreement.id,'billing_line_id',v_line_id,'rate_plan','daily','rate_amount',v_rate_amount::text,'actual_out_at',p_actual_out_at,'pricing_started_at',v_reservation.start_date,'billing_preview',v_preview);
end;$function$;


alter function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) owner to postgres;
revoke all on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) from public,anon;
grant execute on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) to authenticated,service_role;
