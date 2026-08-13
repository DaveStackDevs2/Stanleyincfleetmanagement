-- Repository record of the verified-live pricing-agreement intake and pickup contracts.
-- This migration is data-free. Pickup remains intentionally daily-only and is not wired to the frontend.

create or replace function public.get_pricing_agreement_intake_state()
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_at timestamptz:=clock_timestamp();
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 return jsonb_build_object(
  'status','pricing_agreement_intake_ready',
  'customers',coalesce((select jsonb_agg(jsonb_build_object('customer_id',c.id,'customer_name',c.name,'tekion_customer_number',c.tekion_customer_number) order by c.name,c.id) from public.customers c),'[]'::jsonb),
  'active_pay_types',coalesce((select jsonb_agg(jsonb_build_object('pay_type_rule_id',p.id,'pay_type',p.pay_type,'description',p.description,'is_taxable',p.is_taxable,'sort_order',p.sort_order) order by p.sort_order,p.pay_type,p.id) from public.pay_type_rules p where p.is_active=true),'[]'::jsonb),
  'rate_cards',coalesce((select jsonb_agg(jsonb_build_object('rental_rate_rule_id',r.id,'vehicle_class',r.vehicle_class,'daily_rate',r.daily_rate::text,'weekly_rate',r.weekly_rate::text,'monthly_rate',r.monthly_rate::text,'effective_from',r.effective_from,'effective_to',r.effective_to) order by r.sort_order,r.vehicle_class,r.id) from public.rental_rate_rules r where r.is_active=true and r.effective_from<=v_at and (r.effective_to is null or r.effective_to>v_at) and r.pay_type_rule_id is null),'[]'::jsonb),
  'active_quotes',coalesce((select jsonb_agg(jsonb_build_object('quote_id',q.id,'customer_id',q.customer_id,'customer_name',c.name,'tekion_customer_number',c.tekion_customer_number,'start_date',q.start_date,'expected_return_datetime',q.expected_return_datetime,'reservation_type',q.reservation_type,'notes',q.notes,'transportation_event_id',a.transportation_event_id,'pricing_agreement',jsonb_build_object('pricing_agreement_id',a.id,'origin_type',a.origin_type,'vehicle_class',a.vehicle_class,'pay_type_rule_id',a.pay_type_rule_id,'pay_type',p.pay_type,'initial_rate_plan',a.initial_rate_plan,'current_rate_plan',a.current_rate_plan,'daily_rate',a.daily_rate_snapshot::text,'weekly_rate',a.weekly_rate_snapshot::text,'monthly_rate',a.monthly_rate_snapshot::text,'pricing_started_at',a.pricing_started_at)) order by q.start_date,q.id) from public.quotes q join public.rental_pricing_agreements a on a.quote_id=q.id join public.customers c on c.id=q.customer_id join public.pay_type_rules p on p.id=a.pay_type_rule_id where q.is_active=true and q.status='active' and q.converted_to_reservation_id is null and a.is_active=true),'[]'::jsonb)
 );
end;$function$;

create or replace function public.get_pricing_agreement_pickup_state(p_at timestamptz)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_at timestamptz:=coalesce(p_at,clock_timestamp());
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 return jsonb_build_object('status','pricing_agreement_pickup_ready','observed_at',v_at,
  'reservations',coalesce((select jsonb_agg(jsonb_build_object('reservation_id',r.id,'transportation_event_id',r.transportation_event_id,'customer_id',r.customer_id,'customer_name',c.name,'start_date',r.start_date,'expected_return_datetime',r.expected_return_datetime,'reservation_type',r.reservation_type,'vehicle_class',a.vehicle_class,'pay_type_rule_id',a.pay_type_rule_id,'pay_type',p.pay_type,'pricing_agreement_id',a.id,'initial_rate_plan',a.initial_rate_plan,'current_rate_plan',a.current_rate_plan,'daily_rate',a.daily_rate_snapshot::text,'weekly_rate',a.weekly_rate_snapshot::text,'monthly_rate',a.monthly_rate_snapshot::text,'pricing_started_at',a.pricing_started_at) order by r.start_date,r.id) from public.reservations r join public.rental_pricing_agreements a on a.reservation_id=r.id join public.customers c on c.id=r.customer_id join public.pay_type_rules p on p.id=a.pay_type_rule_id where a.is_active=true and a.pricing_started_at is null and r.status<>'cancelled'),'[]'::jsonb),
  'available_vehicles',coalesce((select jsonb_agg(jsonb_build_object('vehicle_id',v.id,'vin',v.vin,'stock_number',v.stock_number,'model',v.model,'fleet_type',v.fleet_type,'mileage',v.mileage) order by v.model,v.stock_number,v.id) from public.vehicles v where v.status='available'),'[]'::jsonb));
end;$function$;

create or replace function public.activate_pricing_agreement_pickup_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz,p_start_mileage integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_agreement public.rental_pricing_agreements%rowtype; v_reservation public.reservations%rowtype; v_vehicle public.vehicles%rowtype; v_started jsonb; v_vehicle_event uuid; v_contract_period uuid; v_tax jsonb; v_line jsonb;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 if p_reservation_id is null or p_vehicle_id is null or p_actual_out_at is null then raise exception 'Reservation, vehicle, and actual-out timestamp are required' using errcode='22023'; end if;
 if p_start_mileage is not null and p_start_mileage<0 then raise exception 'Start mileage must be zero or greater' using errcode='22023'; end if;
 select * into v_reservation from public.reservations where id=p_reservation_id for update; if not found then raise exception 'Reservation not found' using errcode='P0002'; end if;
 select * into v_agreement from public.rental_pricing_agreements where reservation_id=p_reservation_id and is_active=true for update; if not found then raise exception 'Active pricing agreement not found' using errcode='P0002'; end if;
 if v_agreement.pricing_started_at is not null then raise exception 'Pricing agreement pickup is already active' using errcode='P0001'; end if;
 -- Fail closed until the shared Billing calculation engine authoritatively supports these plans.
 if v_agreement.current_rate_plan<>'daily' then raise exception 'Weekly and monthly pickup pricing are not yet supported' using errcode='0A000'; end if;
 select * into v_vehicle from public.vehicles where id=p_vehicle_id for update; if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
 if v_vehicle.status<>'available' then raise exception 'Vehicle is not available' using errcode='P0001'; end if;
 v_started:=public.start_vehicle_use_state(p_reservation_id,p_vehicle_id,p_actual_out_at);
 begin v_vehicle_event:=(v_started->>'vehicle_event_id')::uuid; v_contract_period:=(v_started->>'contract_period_id')::uuid; exception when others then raise exception 'Vehicle-use activation did not return continuity identifiers' using errcode='P0001'; end;
 v_tax:=public.resolve_billing_tax_state((select pay_type from public.pay_type_rules where id=v_agreement.pay_type_rule_id),v_agreement.daily_rate_snapshot);
 v_line:=public.create_billing_parent_line_state(v_agreement.transportation_event_id,p_reservation_id,p_vehicle_id,(select pay_type from public.pay_type_rules where id=v_agreement.pay_type_rule_id),v_agreement.daily_rate_snapshot,(v_tax->>'tax_amount')::numeric,p_actual_out_at,null,'pricing_agreement_daily',v_vehicle_event,v_contract_period,'initial_assignment',null,null,null,true,null,null,v_agreement.daily_rate_snapshot,null);
 update public.billing_lines set pricing_agreement_id=v_agreement.id,rate_plan_snapshot='daily',rate_amount_snapshot=v_agreement.daily_rate_snapshot where id=(v_line->>'billing_line_id')::uuid;
 update public.rental_pricing_agreements set pricing_started_at=p_actual_out_at,updated_by=v_user where id=v_agreement.id returning * into v_agreement;
 if p_start_mileage is not null then update public.reservations set start_mileage=p_start_mileage where id=p_reservation_id; end if;
 return jsonb_build_object('status','pricing_agreement_pickup_activated','reservation_id',p_reservation_id,'transportation_event_id',v_agreement.transportation_event_id,'vehicle_id',p_vehicle_id,'vehicle_event_id',v_vehicle_event,'contract_period_id',v_contract_period,'pricing_agreement_id',v_agreement.id,'rate_plan','daily','rate_amount',v_agreement.daily_rate_snapshot,'pricing_started_at',v_agreement.pricing_started_at,'billing',v_line);
end;$function$;

alter function public.get_pricing_agreement_intake_state() owner to postgres;
alter function public.get_pricing_agreement_pickup_state(timestamptz) owner to postgres;
alter function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) owner to postgres;
revoke all on function public.get_pricing_agreement_intake_state() from public,anon;
revoke all on function public.get_pricing_agreement_pickup_state(timestamptz) from public,anon;
revoke all on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) from public,anon;
grant execute on function public.get_pricing_agreement_intake_state() to authenticated,service_role;
grant execute on function public.get_pricing_agreement_pickup_state(timestamptz) to authenticated,service_role;
grant execute on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) to authenticated,service_role;
