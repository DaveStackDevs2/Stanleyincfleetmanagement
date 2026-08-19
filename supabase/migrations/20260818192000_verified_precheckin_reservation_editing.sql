-- Repository reconciliation of definitions already applied and independently verified live.
-- Data-free: no production records or controlled-test fixtures are included.

create or replace function public.update_precheckin_reservation_state(p_reservation_id uuid,p_start_date timestamptz,p_expected_return_datetime timestamptz,p_service_advisor text default null,p_ro_number text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_user uuid; v_reservation public.reservations%rowtype; v_agreement public.rental_pricing_agreements%rowtype; v_event public.transportation_events%rowtype;
 v_at timestamptz:=clock_timestamp(); v_expected jsonb; v_changed_fields integer:=0; v_changed text[]:='{}';
 v_advisor text:=nullif(btrim(p_service_advisor),''); v_ro text:=nullif(btrim(p_ro_number),''); v_notes text:=nullif(btrim(p_notes),''); v_field text;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'An active application user is required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication is required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing-agreement permission is required' using errcode='42501'; end if;
 if p_reservation_id is null or p_start_date is null or p_expected_return_datetime is null then raise exception 'Reservation and schedule are required' using errcode='22023'; end if;
 if p_expected_return_datetime<=p_start_date then raise exception 'Scheduled return must be after scheduled start' using errcode='22023'; end if;
 select * into v_reservation from public.reservations where id=p_reservation_id for update;
 if not found then raise exception 'Reservation was not found' using errcode='P0002'; end if;
 if lower(coalesce(v_reservation.status,'')) in ('cancelled','returned') or v_reservation.actual_return_datetime is not null then raise exception 'Reservation is not eligible for pre-check-in editing' using errcode='P0001'; end if;
 select * into v_agreement from public.rental_pricing_agreements where reservation_id=v_reservation.id and transportation_event_id=v_reservation.transportation_event_id and is_active=true for update;
 if not found then raise exception 'Active pricing agreement was not found' using errcode='P0002'; end if;
 select * into v_event from public.transportation_events where id=v_reservation.transportation_event_id for update;
 if not found then raise exception 'Transportation Event was not found' using errcode='P0002'; end if;
 if lower(btrim(coalesce(v_event.status,'')))<>'active' or v_event.closed_at is not null then raise exception 'Active Transportation Event was not found' using errcode='P0002'; end if;
 if v_agreement.pricing_started_at is not null then raise exception 'Pricing has already started' using errcode='P0001'; end if;
 if exists(select 1 from public.v_current_vehicle_continuity c where c.transportation_event_id=v_reservation.transportation_event_id) then raise exception 'Current vehicle continuity prevents pre-check-in editing' using errcode='P0001'; end if;
 if exists(select 1 from public.v_current_open_billing_lines bl where bl.transportation_event_id=v_reservation.transportation_event_id) then raise exception 'Current open billing prevents pre-check-in editing' using errcode='P0001'; end if;
 if v_reservation.start_date is distinct from p_start_date then v_changed:=array_append(v_changed,'scheduled_start'); end if;
 if v_reservation.expected_return_datetime is distinct from p_expected_return_datetime then v_changed:=array_append(v_changed,'scheduled_return'); end if;
 if v_reservation.service_advisor is distinct from v_advisor then v_changed:=array_append(v_changed,'service_advisor'); end if;
 if v_reservation.ro_number is distinct from v_ro then v_changed:=array_append(v_changed,'ro_number'); end if;
 if v_reservation.notes is distinct from v_notes then v_changed:=array_append(v_changed,'notes'); end if;
 foreach v_field in array v_changed loop
   v_changed_fields:=v_changed_fields+1;
   insert into public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata) values
   ('reservation',v_reservation.id::text,'precheckin_reservation_updated',v_field,
    case v_field when 'scheduled_start' then v_reservation.start_date::text when 'scheduled_return' then v_reservation.expected_return_datetime::text when 'service_advisor' then v_reservation.service_advisor when 'ro_number' then v_reservation.ro_number else v_reservation.notes end,
    case v_field when 'scheduled_start' then p_start_date::text when 'scheduled_return' then p_expected_return_datetime::text when 'service_advisor' then v_advisor when 'ro_number' then v_ro else v_notes end,
    v_user::text,jsonb_build_object('transportation_event_id',v_reservation.transportation_event_id,'pricing_agreement_id',v_agreement.id,'origin_type',v_agreement.origin_type,'changed_at',v_at));
 end loop;
 update public.reservations set start_date=p_start_date,expected_return_datetime=p_expected_return_datetime,service_advisor=v_advisor,ro_number=v_ro,notes=v_notes where id=v_reservation.id;
 v_expected:=public.set_expected_return_state(v_reservation.transportation_event_id,p_expected_return_datetime);
 if v_expected->>'status'<>'expected_return_updated' then raise exception 'Expected-return engine did not update the schedule' using errcode='P0001'; end if;
 update public.transportation_events set notes=v_notes,updated_at=v_at where id=v_reservation.transportation_event_id;
 return jsonb_build_object('status',case when v_changed_fields=0 then 'precheckin_reservation_unchanged' else 'precheckin_reservation_updated' end,'reservation_id',v_reservation.id,'transportation_event_id',v_reservation.transportation_event_id,'pricing_agreement_id',v_agreement.id,'changed_fields',v_changed_fields,'changed_at',v_at,
 'reservation',jsonb_build_object('scheduled_start',p_start_date,'scheduled_return',p_expected_return_datetime,'service_advisor',v_advisor,'ro_number',v_ro,'notes',v_notes,'vehicle_id',v_reservation.vehicle_id,'status',v_reservation.status),
 'transportation_event',jsonb_build_object('status',v_event.status,'source_type',v_event.source_type,'source_id',v_event.source_id,'scheduled_return',p_expected_return_datetime,'notes',v_notes));
end;$function$;

alter function public.update_precheckin_reservation_state(uuid,timestamptz,timestamptz,text,text,text) owner to postgres;
revoke all on function public.update_precheckin_reservation_state(uuid,timestamptz,timestamptz,text,text,text) from public,anon;
grant execute on function public.update_precheckin_reservation_state(uuid,timestamptz,timestamptz,text,text,text) to postgres,authenticated,service_role;

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

alter function public.get_pricing_agreement_pickup_state(timestamptz) owner to postgres;
revoke all on function public.get_pricing_agreement_pickup_state(timestamptz) from public,anon;
grant execute on function public.get_pricing_agreement_pickup_state(timestamptz) to postgres,authenticated,service_role;
