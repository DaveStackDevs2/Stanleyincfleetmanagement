-- Repository reconciliation of two verified-live pickup fleet-type compatibility fixes.
-- Data-free: this does not create, assign, or update any vehicle or reservation record.

create or replace function public.start_reservation_vehicle_use_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz)
returns jsonb language plpgsql as $function$
declare
 v_reservation record;
 v_vehicle_fleet_type text;
 v_start_result jsonb;
begin
 select * into v_reservation from public.reservations where id=p_reservation_id for update;
 if not found then raise exception 'Reservation % does not exist',p_reservation_id; end if;

 select fleet_type into v_vehicle_fleet_type from public.vehicles where id=p_vehicle_id;
 if not found then raise exception 'Vehicle % does not exist',p_vehicle_id; end if;

 if lower(btrim(v_vehicle_fleet_type))<>lower(btrim(v_reservation.reservation_type)) then
  raise exception 'Vehicle fleet type % does not match reservation type %',v_vehicle_fleet_type,v_reservation.reservation_type using errcode='22023';
 end if;
 if p_actual_out_at is null then raise exception 'actual_out_at cannot be null'; end if;
 if p_actual_out_at<v_reservation.start_date then
  raise exception 'actual_out_at % is before reservation start_date %',p_actual_out_at,v_reservation.start_date;
 end if;

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
join public.vehicles as v
  on v.model = r.requested_model
 and lower(btrim(v.fleet_type)) = lower(btrim(r.reservation_type))
left join public.v_current_vehicle_continuity c on c.vehicle_id=v.id
left join public.transportation_events te on te.id=c.transportation_event_id
where r.status is distinct from 'cancelled'::text;
alter view public.v_reservation_vehicle_candidates owner to postgres;
