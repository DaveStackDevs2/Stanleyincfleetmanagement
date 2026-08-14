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
  'status','pricing_agreement_intake_ready','observed_at',v_at,
  'customers',coalesce((select jsonb_agg(jsonb_build_object('customer_id',c.id,'tekion_customer_number',c.tekion_customer_number,'name',c.name,'phone',c.phone,'email',c.email,'created_at',c.created_at) order by lower(btrim(c.name)),c.tekion_customer_number,c.id) from public.customers c),'[]'::jsonb),
  'pay_types',coalesce((select jsonb_agg(jsonb_build_object('pay_type_rule_id',p.id,'pay_type',p.pay_type,'description',p.description,'is_taxable',p.is_taxable,'sort_order',p.sort_order) order by p.sort_order,lower(btrim(p.pay_type)),p.id) from public.pay_type_rules p where p.is_active=true and coalesce(p.active,false)=true),'[]'::jsonb),
  'rate_cards',coalesce((select jsonb_agg(jsonb_build_object('rental_rate_rule_id',r.id,'vehicle_class',r.vehicle_class,'daily_rate',r.daily_rate::text,'weekly_rate',r.weekly_rate::text,'monthly_rate',r.monthly_rate::text,'sort_order',r.sort_order,'effective_from',r.effective_from,'effective_to',r.effective_to) order by r.sort_order,lower(btrim(r.vehicle_class)),r.id) from public.rental_rate_rules r where r.is_active=true and r.effective_from<=v_at and (r.effective_to is null or r.effective_to>v_at)),'[]'::jsonb),
  'quotes',coalesce((select jsonb_agg(jsonb_build_object(
    'quote_id',q.id,'created_at',q.created_at,'status',q.status,'reservation_type',q.reservation_type,
    'start_date',q.start_date,'expected_return_datetime',q.expected_return_datetime,'notes',q.notes,
    'customer',jsonb_build_object('customer_id',c.id,'tekion_customer_number',c.tekion_customer_number,'name',c.name,'phone',c.phone,'email',c.email),
    'transportation_event_id',a.transportation_event_id,'pricing_agreement_id',a.id,'origin_type',a.origin_type,'vehicle_class',a.vehicle_class,
    'rental_rate_rule_id',a.rental_rate_rule_id,'pay_type_rule_id',a.pay_type_rule_id,'pay_type',p.pay_type,
    'initial_rate_plan',a.initial_rate_plan,'current_rate_plan',a.current_rate_plan,'daily_rate',a.daily_rate_snapshot::text,
    'weekly_rate',a.weekly_rate_snapshot::text,'monthly_rate',a.monthly_rate_snapshot::text,'pricing_started_at',a.pricing_started_at) order by q.start_date,q.created_at,q.id)
   from public.quotes q
   join public.rental_pricing_agreements a on a.quote_id=q.id and a.origin_type='quote' and a.reservation_id is null and a.is_active=true
   join public.transportation_events te on te.id=a.transportation_event_id and te.source_type='quote' and te.source_id=q.id and te.status='active'
   join public.customers c on c.id=q.customer_id
   join public.pay_type_rules p on p.id=a.pay_type_rule_id
   where q.is_active=true and q.status='active' and q.converted_to_reservation_id is null),'[]'::jsonb)
 );
end;$function$;

create or replace function public.get_pricing_agreement_pickup_state(p_reference_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_vin_lock_lead_days integer:=0; v_items jsonb;
begin
 if p_reference_at is null then raise exception 'Reference timestamp is required' using errcode='22023'; end if;
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 select coalesce((setting_value #>> '{}')::integer,0) into v_vin_lock_lead_days from public.admin_settings where setting_key='reservation_vin_lock_lead_days';
 v_vin_lock_lead_days:=coalesce(v_vin_lock_lead_days,0);
 select coalesce(jsonb_agg(jsonb_build_object(
   'reservation_id',r.id,'transportation_event_id',r.transportation_event_id,'reservation_status',r.status,
   'reservation_type',r.reservation_type,'start_date',r.start_date,'expected_return_datetime',r.expected_return_datetime,
   'service_advisor',r.service_advisor,'ro_number',r.ro_number,'vehicle_class',a.vehicle_class,'assigned_vehicle_id',r.vehicle_id,
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
      order by case vc.candidate_state when 'ready' then 0 when 'pending_return' then 1 else 2 end,
        vc.expected_return_snapshot asc nulls last,vc.stock_number asc nulls last,vc.vin asc nulls last)
      from public.v_reservation_vehicle_candidates vc where vc.reservation_id=r.id),'[]'::jsonb)) order by r.start_date,r.id),'[]'::jsonb)
 into v_items
 from public.reservations r
 join public.rental_pricing_agreements a on a.reservation_id=r.id and a.transportation_event_id=r.transportation_event_id and a.is_active=true and a.pricing_started_at is null
 join public.transportation_events te on te.id=r.transportation_event_id and te.status='active'
 join public.customers c on c.id=r.customer_id
 join public.pay_type_rules p on p.id=a.pay_type_rule_id
 where r.status is distinct from 'cancelled' and r.actual_return_datetime is null;
 return jsonb_build_object('status','pricing_agreement_pickup_ready','reference_at',p_reference_at,'vin_lock_lead_days',v_vin_lock_lead_days,'items',v_items);
end;$function$;

create or replace function public.activate_pricing_agreement_pickup_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz,p_start_mileage integer default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_user uuid; v_agreement public.rental_pricing_agreements%rowtype; v_reservation public.reservations%rowtype; v_vehicle public.vehicles%rowtype;
 v_pay_type text; v_started jsonb; v_continuity jsonb; v_vehicle_event uuid; v_contract_period uuid; v_line jsonb; v_line_id uuid; v_preview jsonb;
 v_current_vehicle_id uuid; v_existing_line uuid;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.case_start')
    or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then
  raise exception 'Case start and pricing agreement management permissions required' using errcode='42501';
 end if;
 if p_reservation_id is null or p_vehicle_id is null or p_actual_out_at is null then raise exception 'Reservation, vehicle, and actual-out timestamp are required' using errcode='22023'; end if;
 if p_start_mileage is not null and p_start_mileage<0 then raise exception 'Start mileage must be zero or greater' using errcode='22023'; end if;
 select * into v_reservation from public.reservations where id=p_reservation_id for update;
 if not found then raise exception 'Reservation not found' using errcode='P0002'; end if;
 select * into v_agreement from public.rental_pricing_agreements where reservation_id=v_reservation.id and transportation_event_id=v_reservation.transportation_event_id and is_active=true for update;
 if not found then raise exception 'Active pricing agreement not found' using errcode='P0002'; end if;
 if lower(btrim(v_reservation.status))='cancelled' or v_reservation.actual_return_datetime is not null then raise exception 'Cancelled or returned reservations cannot be activated' using errcode='P0001'; end if;
 if p_actual_out_at<v_reservation.start_date then raise exception 'Actual out timestamp cannot precede reservation start' using errcode='22023'; end if;
 if v_agreement.current_rate_plan<>'daily' then raise exception 'Weekly and monthly pickup pricing are not yet supported' using errcode='0A000'; end if;
 if v_agreement.daily_rate_snapshot is null or v_agreement.daily_rate_snapshot<0 or v_agreement.daily_rate_snapshot in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Daily pricing snapshot is invalid' using errcode='P0001'; end if;
 select p.pay_type into v_pay_type from public.pay_type_rules p where p.id=v_agreement.pay_type_rule_id;
 if v_pay_type is null then raise exception 'Pricing pay type not found' using errcode='P0002'; end if;
 select * into v_vehicle from public.vehicles where id=p_vehicle_id and is_retired=false for update;
 if not found then raise exception 'Vehicle is unavailable' using errcode='P0002'; end if;
 if lower(btrim(v_vehicle.model))<>lower(btrim(v_agreement.vehicle_class)) then raise exception 'Vehicle does not match pricing agreement vehicle class' using errcode='22023'; end if;
 if v_reservation.vehicle_id is not null and v_reservation.vehicle_id is distinct from p_vehicle_id then raise exception 'Reservation has a different preassigned vehicle' using errcode='P0001'; end if;
 select c.vehicle_id into v_current_vehicle_id
 from public.v_current_vehicle_continuity c where c.transportation_event_id=v_reservation.transportation_event_id limit 1;
 select bl.id into v_existing_line from public.billing_lines bl where bl.transportation_event_id=v_reservation.transportation_event_id
   and bl.parent_billing_line_id is null and bl.is_open=true
   order by bl.start_time desc nulls last,bl.created_at desc,bl.id desc limit 1;
 if v_agreement.pricing_started_at is not null then
  if v_current_vehicle_id=p_vehicle_id and v_existing_line is not null then
   return jsonb_build_object('status','pricing_agreement_pickup_already_active','reservation_id',p_reservation_id,'transportation_event_id',v_reservation.transportation_event_id,'pricing_agreement_id',v_agreement.id,'vehicle_id',p_vehicle_id,'billing_line_id',v_existing_line,'pricing_started_at',v_agreement.pricing_started_at);
  end if;
  raise exception 'Existing pickup continuity or billing is inconsistent' using errcode='P0001';
 end if;
 if v_current_vehicle_id is not null or v_existing_line is not null then raise exception 'Pre-pickup case already has continuity or billing' using errcode='P0001'; end if;
 if exists(select 1 from public.v_current_vehicle_continuity c where c.vehicle_id=p_vehicle_id) then raise exception 'Vehicle is currently assigned to another case' using errcode='P0001'; end if;
 v_started:=public.start_reservation_vehicle_use_state(p_reservation_id,p_vehicle_id,p_actual_out_at);
 v_continuity:=v_started->'continuity_result';
 begin v_vehicle_event:=(v_continuity->>'vehicle_event_id')::uuid; v_contract_period:=(v_continuity->>'contract_period_id')::uuid;
 exception when invalid_text_representation then raise exception 'Vehicle-use activation returned malformed continuity identifiers' using errcode='P0001'; end;
 if v_vehicle_event is null or v_contract_period is null then raise exception 'Vehicle-use activation did not return continuity identifiers' using errcode='P0001'; end if;
 update public.reservations set status='active',start_mileage=coalesce(p_start_mileage,start_mileage) where id=p_reservation_id;
 update public.vehicle_events set created_by=v_user,updated_by=v_user where id=v_vehicle_event;
 update public.contract_periods set created_by=v_user,updated_by=v_user where id=v_contract_period;
 v_line:=public.create_billing_parent_line_state(v_reservation.transportation_event_id,p_reservation_id,p_vehicle_id,v_pay_type,v_agreement.daily_rate_snapshot,null,p_actual_out_at,null,'pricing_agreement_daily',v_vehicle_event,v_contract_period,'initial_assignment',null,null,null,true,null,null,v_agreement.daily_rate_snapshot,null);
 if v_line->>'status'<>'parent_billing_line_created' then raise exception 'Authoritative parent billing line was not created' using errcode='P0001'; end if;
 begin v_line_id:=(v_line->>'parent_billing_line_id')::uuid; exception when invalid_text_representation then raise exception 'Billing engine returned a malformed parent billing line identifier' using errcode='P0001'; end;
 if v_line_id is null then raise exception 'Billing engine returned no parent billing line' using errcode='P0001'; end if;
 update public.billing_lines set pricing_agreement_id=v_agreement.id,rate_plan_snapshot='daily',rate_amount_snapshot=v_agreement.daily_rate_snapshot where id=v_line_id;
 update public.rental_pricing_agreements set pricing_started_at=p_actual_out_at,updated_by=v_user,updated_at=clock_timestamp() where id=v_agreement.id returning * into v_agreement;
 v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,clock_timestamp());
 if v_preview->>'status'<>'billing_preview_ready' then raise exception 'Current authoritative billing preview is not ready' using errcode='P0001'; end if;
 return jsonb_build_object('status','pricing_agreement_pickup_activated','reservation_id',p_reservation_id,'transportation_event_id',v_reservation.transportation_event_id,'vehicle_id',p_vehicle_id,'vehicle_event_id',v_vehicle_event,'contract_period_id',v_contract_period,'pricing_agreement_id',v_agreement.id,'billing_line_id',v_line_id,'rate_plan','daily','rate_amount',v_agreement.daily_rate_snapshot::text,'pricing_started_at',v_agreement.pricing_started_at,'billing_preview',v_preview);
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
