-- Rental payment and Extension workflow correction. Data-free; no SO number or bulk Loaner engine.
ALTER TABLE public.billing_lines ADD COLUMN IF NOT EXISTS rental_paid_in_full boolean NOT NULL DEFAULT false;
ALTER TABLE public.billing_lines ADD COLUMN IF NOT EXISTS rental_paid_at timestamptz;
ALTER TABLE public.billing_lines ADD COLUMN IF NOT EXISTS rental_paid_by_user_id uuid;
DO $migration$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='billing_lines_rental_paid_by_user_id_fkey') THEN ALTER TABLE public.billing_lines ADD CONSTRAINT billing_lines_rental_paid_by_user_id_fkey FOREIGN KEY (rental_paid_by_user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='ck_billing_lines_rental_payment_consistency') THEN ALTER TABLE public.billing_lines ADD CONSTRAINT ck_billing_lines_rental_payment_consistency CHECK ((rental_paid_in_full AND rental_paid_at IS NOT NULL AND rental_paid_by_user_id IS NOT NULL) OR (NOT rental_paid_in_full AND rental_paid_at IS NULL AND rental_paid_by_user_id IS NULL)); END IF;
END $migration$;

CREATE OR REPLACE FUNCTION public.get_rental_payment_state(p_transportation_event_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_actor uuid; v_reservation uuid; v_lines jsonb; v_charge numeric; v_tax numeric; v_unpaid_charge numeric; v_unpaid_tax numeric;
BEGIN
 SELECT id INTO v_actor FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true; IF v_actor IS NULL THEN RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501'; END IF;
 SELECT r.id INTO v_reservation FROM public.reservations r WHERE r.transportation_event_id=p_transportation_event_id AND lower(coalesce(r.reservation_type,'')) LIKE '%rental%' ORDER BY r.created_at LIMIT 1;
 IF v_reservation IS NULL THEN RAISE EXCEPTION 'Rental case was not found' USING ERRCODE='P0002'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('billing_line_id',b.id,'purpose',CASE WHEN b.line_type='rental_extension' THEN 'Rental Extension' ELSE 'Original Rental' END,'line_type',b.line_type,'start_at',b.start_time,'through_at',b.end_time,'charge',b.amount::text,'tax',coalesce(b.tax_amount,0)::text,'total',(coalesce(b.amount,0)+coalesce(b.tax_amount,0))::text,'rental_paid_in_full',b.rental_paid_in_full,'payment_status',CASE WHEN b.rental_paid_in_full THEN 'Paid in Full' ELSE 'Not Paid' END,'rental_paid_at',b.rental_paid_at) ORDER BY b.start_time,b.created_at,b.id),'[]'::jsonb),coalesce(sum(b.amount),0),coalesce(sum(b.tax_amount),0),coalesce(sum(b.amount) FILTER(WHERE NOT b.rental_paid_in_full),0),coalesce(sum(b.tax_amount) FILTER(WHERE NOT b.rental_paid_in_full),0) INTO v_lines,v_charge,v_tax,v_unpaid_charge,v_unpaid_tax FROM public.billing_lines b WHERE b.transportation_event_id=p_transportation_event_id AND b.reservation_id=v_reservation AND b.parent_billing_line_id IS NULL AND b.line_type IN ('initial_assignment','rental_extension');
 RETURN jsonb_build_object('status','rental_payment_state_ready','reservation_id',v_reservation,'transportation_event_id',p_transportation_event_id,'lines',v_lines,'contractual_charge',v_charge::text,'contractual_tax',v_tax::text,'contractual_total',(v_charge+v_tax)::text,'unpaid_charge',v_unpaid_charge::text,'unpaid_tax',v_unpaid_tax::text,'unpaid_total',(v_unpaid_charge+v_unpaid_tax)::text,'overall_paid_in_full',(v_unpaid_charge+v_unpaid_tax=0));
END $function$;

CREATE OR REPLACE FUNCTION public.mark_rental_billing_line_paid_in_full_state(p_billing_line_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_user uuid; v_line public.billing_lines%rowtype;
BEGIN
 SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true; IF v_user IS NULL THEN RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501'; END IF; IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501'; END IF;
 SELECT b.* INTO v_line FROM public.billing_lines b JOIN public.reservations r ON r.id=b.reservation_id WHERE b.id=p_billing_line_id AND b.parent_billing_line_id IS NULL AND b.line_type IN ('initial_assignment','rental_extension') AND lower(coalesce(r.reservation_type,'')) LIKE '%rental%' FOR UPDATE OF b; IF NOT FOUND THEN RAISE EXCEPTION 'Eligible Rental parent billing line not found' USING ERRCODE='P0002'; END IF;
 IF NOT v_line.rental_paid_in_full THEN UPDATE public.billing_lines SET rental_paid_in_full=true,rental_paid_at=clock_timestamp(),rental_paid_by_user_id=v_user,updated_at=clock_timestamp() WHERE id=v_line.id; INSERT INTO public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata) VALUES ('billing_line',v_line.id::text,'rental_paid_in_full_recorded','rental_paid_in_full','false','true',v_user::text,jsonb_build_object('transportation_event_id',v_line.transportation_event_id,'reservation_id',v_line.reservation_id)); END IF;
 RETURN public.get_rental_payment_state(v_line.transportation_event_id);
END $function$;

create or replace function public.activate_pricing_agreement_pickup_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz,p_start_mileage integer default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_user uuid; v_agreement public.rental_pricing_agreements%rowtype; v_reservation public.reservations%rowtype; v_vehicle public.vehicles%rowtype;
 v_pay_type public.pay_type_rules%rowtype; v_started jsonb; v_billing_result jsonb; v_vehicle_event uuid; v_contract_period uuid; v_line_id uuid; v_preview jsonb; v_rate_amount numeric;
 v_current_vehicle_id uuid; v_existing_line uuid; v_tax_sync jsonb; v_tax_count integer; v_tax_sum numeric; v_payment jsonb;
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
   return jsonb_build_object('status','pricing_agreement_pickup_already_active','reservation_id',p_reservation_id,'transportation_event_id',v_reservation.transportation_event_id,'pricing_agreement_id',v_agreement.id,'vehicle_id',p_vehicle_id,'billing_line_id',v_existing_line,'pricing_started_at',v_agreement.pricing_started_at);
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
 v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime);
  if v_preview->>'status'='billing_preview_ready' then
   update public.billing_lines set amount=(v_preview->>'subtotal')::numeric,tax_amount=(v_preview->>'tax_amount')::numeric,end_time=v_reservation.expected_return_datetime where id=v_line_id;
   v_tax_sync:=public.ensure_tax_child_line_state(v_line_id);
   select count(*),sum(amount) into v_tax_count,v_tax_sum from public.billing_lines where parent_billing_line_id=v_line_id and line_type='tax';
   if (((v_preview->>'tax_amount')::numeric>0 and (v_tax_count<>1 or v_tax_sum is distinct from (v_preview->>'tax_amount')::numeric)) or ((v_preview->>'tax_amount')::numeric=0 and v_tax_count<>0)) then raise exception 'Pickup tax child does not match authoritative tax'; end if;
   v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime);
  end if;
  if v_preview->>'status'<>'billing_preview_ready' then raise exception 'Activated pickup could not be loaded by Billing' using errcode='P0001'; end if;
 v_payment:=public.get_rental_payment_state(v_reservation.transportation_event_id);
 return jsonb_build_object('rental_payment_state',v_payment,'status','pricing_agreement_pickup_activated','reservation_id',v_reservation.id,'transportation_event_id',v_reservation.transportation_event_id,'vehicle_id',p_vehicle_id,'vehicle_event_id',v_vehicle_event,'contract_period_id',v_contract_period,'pricing_agreement_id',v_agreement.id,'billing_line_id',v_line_id,'rate_plan','daily','rate_amount',v_rate_amount::text,'actual_out_at',p_actual_out_at,'pricing_started_at',v_reservation.start_date,'billing_preview',v_preview);
end;$function$;


CREATE OR REPLACE FUNCTION public.preview_rental_extension_state(p_reservation_id uuid,p_new_expected_return_at timestamptz) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_te uuid; v_old_return timestamptz; v_line public.billing_lines%rowtype; v_preview jsonb; v_old_preview jsonb; v_add_charge numeric; v_add_tax numeric; v_add_total numeric;
BEGIN
 SELECT r.transportation_event_id,coalesce(te.expected_return_at,r.expected_return_datetime) INTO v_te,v_old_return FROM public.reservations r JOIN public.transportation_events te ON te.id=r.transportation_event_id WHERE r.id=p_reservation_id;
 IF v_te IS NULL THEN RAISE EXCEPTION 'Rental Extension preview is unavailable' USING ERRCODE='P0002'; END IF;
 IF p_new_expected_return_at IS NULL OR v_old_return IS NULL OR p_new_expected_return_at<=v_old_return THEN RAISE EXCEPTION 'New return must be later than current return' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_line FROM public.billing_lines WHERE transportation_event_id=v_te AND reservation_id=p_reservation_id AND parent_billing_line_id IS NULL AND line_type IN ('initial_assignment','rental_extension') AND is_open ORDER BY start_time DESC NULLS LAST,id DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Current Rental billing line is unavailable' USING ERRCODE='P0002'; END IF;
 v_old_preview:=public.get_billing_preview_state(v_te,v_old_return); v_preview:=public.get_billing_preview_state(v_te,p_new_expected_return_at);
 IF v_old_preview->>'status' IS DISTINCT FROM 'billing_preview_ready' OR v_preview->>'status' IS DISTINCT FROM 'billing_preview_ready' THEN RAISE EXCEPTION 'Authoritative Rental Extension preview is not ready' USING ERRCODE='P0001'; END IF;
 IF (v_preview->>'current_billing_line_id')::uuid IS DISTINCT FROM v_line.id OR (v_old_preview->>'current_billing_line_id')::uuid IS DISTINCT FROM v_line.id THEN RAISE EXCEPTION 'Rental Extension preview current line changed' USING ERRCODE='40001'; END IF;
 IF v_preview->>'accumulated_subtotal' IS NULL OR v_preview->>'accumulated_tax' IS NULL OR v_preview->>'accumulated_total' IS NULL OR v_old_preview->>'accumulated_subtotal' IS NULL OR v_old_preview->>'accumulated_tax' IS NULL OR v_old_preview->>'accumulated_total' IS NULL THEN RAISE EXCEPTION 'Authoritative Rental Extension money is unavailable' USING ERRCODE='P0001'; END IF;
 v_add_charge:=(v_preview->>'accumulated_subtotal')::numeric-(v_old_preview->>'accumulated_subtotal')::numeric; v_add_tax:=(v_preview->>'accumulated_tax')::numeric-(v_old_preview->>'accumulated_tax')::numeric; v_add_total:=(v_preview->>'accumulated_total')::numeric-(v_old_preview->>'accumulated_total')::numeric;
 IF v_add_charge<0 OR v_add_tax<0 OR v_add_total<0 THEN RAISE EXCEPTION 'Authoritative Rental Extension delta is invalid' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('status','rental_extension_preview_ready','reservation_id',p_reservation_id,'transportation_event_id',v_te,'current_parent_billing_line_id',v_line.id,'previous_expected_return_at',v_old_return,'proposed_expected_return_at',p_new_expected_return_at,'additional_charge',v_add_charge::text,'additional_tax',v_add_tax::text,'additional_total',v_add_total::text,'billing_preview',v_preview);
END $function$;

CREATE OR REPLACE VIEW public.v_warning_center_warning_items WITH (security_invoker=true) AS SELECT 'dependency_warning'::text item_type,d.id source_id,d.reservation_id,d.vehicle_id,d.risk_level,d.status source_status,d.expected_return_snapshot,NULL::uuid contract_period_id,NULL::text reminder_state,'Dependency requires near-term attention'::text message FROM public.reservation_vehicle_dependencies d WHERE d.status IN ('pending_return','ready','conflict') AND d.risk_level IN ('at_risk','must_return') UNION ALL SELECT 'contract_reminder',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,m.contract_period_id,m.reminder_state,'Contract/reminder action needed soon' FROM public.v_contract_period_monitoring m WHERE m.reminder_state IN ('renew_now','swap_required') UNION ALL SELECT 'unpaid_rental',te.id,r.id,min(b.vehicle_id),NULL::text,te.status,te.expected_return_at,NULL::uuid,NULL::text,'Rental has an unpaid balance. Balance Due: $'||(sum(b.amount)+sum(coalesce(b.tax_amount,0)))::text FROM public.transportation_events te JOIN public.reservations r ON r.transportation_event_id=te.id JOIN public.billing_lines b ON b.reservation_id=r.id AND b.parent_billing_line_id IS NULL AND b.line_type IN ('initial_assignment','rental_extension') AND NOT b.rental_paid_in_full WHERE lower(coalesce(r.reservation_type,'')) LIKE '%rental%' AND lower(btrim(te.status))='active' GROUP BY te.id,r.id,te.status,te.expected_return_at;

CREATE OR REPLACE FUNCTION public.get_warning_center_counts_state() RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $$ SELECT jsonb_build_object('status','warning_center_counts_ready','critical_count',(SELECT count(*) FROM public.v_warning_center_critical_items),'warning_count',(SELECT count(*) FROM public.v_warning_center_warning_items),'review_count',(SELECT count(*) FROM public.v_warning_center_review_items)); $$;

ALTER FUNCTION public.get_rental_payment_state(uuid) OWNER TO postgres; ALTER FUNCTION public.mark_rental_billing_line_paid_in_full_state(uuid) OWNER TO postgres; ALTER FUNCTION public.preview_rental_extension_state(uuid,timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_rental_payment_state(uuid),public.mark_rental_billing_line_paid_in_full_state(uuid),public.preview_rental_extension_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role; GRANT EXECUTE ON FUNCTION public.get_rental_payment_state(uuid),public.mark_rental_billing_line_paid_in_full_state(uuid),public.preview_rental_extension_state(uuid,timestamptz) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.billing_lines FROM authenticated,anon;


DO $migration$
DECLARE v_definition text; v_old text:=E'IF v_preview_end < v_billing_start THEN\n        RAISE EXCEPTION ''Preview timestamp precedes the current billing segment'' USING ERRCODE = ''22023'';\n    END IF;'; v_new text:=E'IF v_preview_end < v_billing_start THEN\n        IF v_current_line.line_type = ''rental_extension'' AND v_current_line.extended_from_billing_line_id IS NOT NULL THEN\n            v_preview_end := v_billing_start; -- valid future-start Extension: zero elapsed Extension days\n        ELSE\n            RAISE EXCEPTION ''Preview timestamp precedes the current billing segment'' USING ERRCODE = ''22023'';\n        END IF;\n    END IF;';
BEGIN v_definition:=replace(pg_get_functiondef('public.get_billing_preview_state(uuid,timestamptz)'::regprocedure),chr(13),''); IF strpos(v_definition,v_new)>0 THEN RETURN; END IF; IF strpos(v_definition,v_old)=0 THEN RAISE EXCEPTION 'Billing preview future-start guard has drifted'; END IF; EXECUTE replace(v_definition,v_old,v_new); END $migration$;

CREATE OR REPLACE FUNCTION public.create_extension_billing_line_state(p_parent_billing_line_id uuid,p_extension_amount numeric,p_extension_tax_amount numeric,p_new_expected_return_at timestamptz DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE v_parent public.billing_lines%rowtype; v_result jsonb;
BEGIN
 SELECT * INTO v_parent FROM public.billing_lines WHERE id=p_parent_billing_line_id AND parent_billing_line_id IS NULL AND line_type IS DISTINCT FROM 'tax' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Parent billing line does not exist or is a tax line'; END IF;
 IF v_parent.is_open OR v_parent.end_time IS NULL OR v_parent.start_time IS NULL OR v_parent.end_time<v_parent.start_time THEN RAISE EXCEPTION 'Prior Rental billing line must be closed at a valid expected-return boundary'; END IF;
 IF p_new_expected_return_at IS NULL OR p_new_expected_return_at<=v_parent.end_time THEN RAISE EXCEPTION 'Extension end must be later than prior expected return'; END IF;
 IF p_extension_amount IS NULL OR p_extension_amount<0 OR (p_extension_tax_amount IS NOT NULL AND p_extension_tax_amount<0) THEN RAISE EXCEPTION 'Extension amounts must be non-negative'; END IF;
 v_result:=public.create_billing_parent_line_state(v_parent.transportation_event_id,v_parent.reservation_id,v_parent.vehicle_id,v_parent.pay_type,p_extension_amount,p_extension_tax_amount,v_parent.end_time,p_new_expected_return_at,v_parent.source_rule,v_parent.vehicle_event_id,v_parent.contract_period_id,'rental_extension',v_parent.warranty_provider_id,v_parent.default_covered_days_snapshot,v_parent.covered_days_override,true,NULL,v_parent.id,v_parent.default_daily_rate_snapshot,v_parent.daily_rate_override);
 RETURN jsonb_build_object('status','extension_billing_line_created','parent_billing_line_id',p_parent_billing_line_id,'new_billing_line_id',v_result->>'parent_billing_line_id','result',v_result);
END $function$;

CREATE OR REPLACE FUNCTION public.accept_extension_commit_state(p_transportation_event_id uuid,p_current_billing_line_id uuid,p_new_expected_return_at timestamptz,p_extension_amount numeric,p_extension_tax_amount numeric DEFAULT NULL,p_reason_code text DEFAULT NULL,p_optional_note text DEFAULT NULL,p_entered_by_user_id uuid DEFAULT NULL,p_dependency_id_to_escalate uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE v_old_expected_return_at timestamptz; v_expected_return_result jsonb; v_note_result jsonb; v_close_result jsonb; v_extension_line_result jsonb; v_escalation_result jsonb:=NULL;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.transportation_events WHERE id=p_transportation_event_id) THEN RAISE EXCEPTION 'Transportation event does not exist'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.billing_lines WHERE id=p_current_billing_line_id AND is_open=true AND line_type IS DISTINCT FROM 'tax') THEN RAISE EXCEPTION 'Open current billing line does not exist'; END IF;
 IF p_reason_code IS NULL OR btrim(p_reason_code)='' THEN RAISE EXCEPTION 'Reason code is required for accepted extension'; END IF;
 IF p_extension_amount IS NULL OR p_extension_amount<0 OR (p_extension_tax_amount IS NOT NULL AND p_extension_tax_amount<0) THEN RAISE EXCEPTION 'Extension amounts must be non-negative'; END IF;
 IF p_entered_by_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.app_users WHERE id=p_entered_by_user_id) THEN RAISE EXCEPTION 'User does not exist'; END IF;
 IF p_dependency_id_to_escalate IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.reservation_vehicle_dependencies WHERE id=p_dependency_id_to_escalate) THEN RAISE EXCEPTION 'Dependency does not exist'; END IF;
 SELECT expected_return_at INTO v_old_expected_return_at FROM public.transportation_events WHERE id=p_transportation_event_id FOR UPDATE;
 IF v_old_expected_return_at IS NULL OR p_new_expected_return_at<=v_old_expected_return_at THEN RAISE EXCEPTION 'New expected return must be later'; END IF;
 v_expected_return_result:=public.set_expected_return_state(p_transportation_event_id,p_new_expected_return_at);
 v_note_result:=public.add_estimated_return_change_note_state(p_transportation_event_id,v_old_expected_return_at,p_new_expected_return_at,p_reason_code,p_optional_note,p_entered_by_user_id);
 v_close_result:=public.close_billing_line_state(p_current_billing_line_id,v_old_expected_return_at);
 v_extension_line_result:=public.create_extension_billing_line_state(p_current_billing_line_id,p_extension_amount,p_extension_tax_amount,p_new_expected_return_at);
 IF p_dependency_id_to_escalate IS NOT NULL THEN v_escalation_result:=public.escalate_dependency_to_critical_state(p_dependency_id_to_escalate,p_entered_by_user_id); END IF;
 RETURN jsonb_build_object('status',CASE WHEN p_dependency_id_to_escalate IS NOT NULL THEN 'accepted_with_conflict_escalation' ELSE 'accepted' END,'transportation_event_id',p_transportation_event_id,'current_billing_line_id',p_current_billing_line_id,'expected_return_result',v_expected_return_result,'note_result',v_note_result,'close_result',v_close_result,'extension_line_result',v_extension_line_result,'dependency_escalation_result',v_escalation_result);
END $function$;

CREATE OR REPLACE FUNCTION public.accept_case_extension_and_get_unified_payload_state(p_reservation_id uuid,p_new_expected_return_at timestamptz,p_extension_amount numeric,p_extension_tax_amount numeric DEFAULT NULL,p_reason_code text DEFAULT NULL,p_optional_note text DEFAULT NULL,p_entered_by_user_id uuid DEFAULT NULL,p_escalate_current_dependency boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_user uuid; v_candidate record; v_current_line public.billing_lines%rowtype; v_preview jsonb; v_action jsonb; v_unified jsonb; v_new_line uuid;
BEGIN
 SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true; IF v_user IS NULL THEN RAISE EXCEPTION 'Billing action access denied' USING ERRCODE='42501'; END IF; IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'Billing action requires AAL2' USING ERRCODE='42501'; END IF; IF p_entered_by_user_id IS NOT NULL AND p_entered_by_user_id<>v_user THEN RAISE EXCEPTION 'Billing actor mismatch' USING ERRCODE='42501'; END IF;
 IF p_reason_code IS NULL OR btrim(p_reason_code)='' THEN RAISE EXCEPTION 'Extension reason is required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_candidate FROM public.v_reservation_extension_candidate_state WHERE reservation_id=p_reservation_id AND parent_billing_line_id IS NOT NULL ORDER BY start_time DESC NULLS LAST,parent_billing_line_id DESC LIMIT 1; IF NOT FOUND THEN RAISE EXCEPTION 'No extension-eligible billing line exists' USING ERRCODE='P0002'; END IF;
 SELECT * INTO v_current_line FROM public.billing_lines WHERE id=v_candidate.parent_billing_line_id AND reservation_id=p_reservation_id AND transportation_event_id=v_candidate.transportation_event_id AND parent_billing_line_id IS NULL AND line_type IN ('initial_assignment','rental_extension') AND is_open FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Current extension billing line changed' USING ERRCODE='40001'; END IF;
 v_preview:=public.preview_rental_extension_state(p_reservation_id,p_new_expected_return_at); IF (v_preview->>'current_parent_billing_line_id')::uuid IS DISTINCT FROM v_current_line.id THEN RAISE EXCEPTION 'Rental Extension preview current line changed' USING ERRCODE='40001'; END IF;
 v_action:=public.accept_reservation_extension_state(p_reservation_id,p_new_expected_return_at,(v_preview->>'additional_charge')::numeric,(v_preview->>'additional_tax')::numeric,p_reason_code,p_optional_note,v_user,p_escalate_current_dependency);
 v_new_line:=(v_action->'extension_commit_result'->'extension_line_result'->>'new_billing_line_id')::uuid; IF v_new_line IS NULL THEN RAISE EXCEPTION 'Extension engine did not return the successor billing line'; END IF;
 v_unified:=public.get_unified_case_payload_state(p_reservation_id);
 RETURN jsonb_build_object('status','case_extension_accepted_and_loaded','reservation_id',p_reservation_id,'transportation_event_id',v_candidate.transportation_event_id,'previous_expected_return_at',v_preview->>'previous_expected_return_at','new_expected_return_at',p_new_expected_return_at,'previous_billing_line_id',v_current_line.id,'new_billing_line_id',v_new_line,'additional_charge',v_preview->>'additional_charge','additional_tax',v_preview->>'additional_tax','additional_total',v_preview->>'additional_total','submitted_amounts_ignored',true,'action_result',v_action,'unified_case_payload',v_unified,'rental_payment_state',public.get_rental_payment_state(v_candidate.transportation_event_id));
END $function$;

ALTER FUNCTION public.create_extension_billing_line_state(uuid,numeric,numeric,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) OWNER TO postgres;
ALTER FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_extension_billing_line_state(uuid,numeric,numeric,timestamptz),public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_extension_billing_line_state(uuid,numeric,numeric,timestamptz),public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) TO authenticated;
