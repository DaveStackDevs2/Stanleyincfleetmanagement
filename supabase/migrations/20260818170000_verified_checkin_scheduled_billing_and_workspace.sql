-- Data-free reconciliation of verified-live Check-in / Pickup timing and Billing workspace eligibility.
-- Normal pre-check-in Reservations have neither current continuity nor current billing and are intentionally excluded.

create or replace function public.activate_pricing_agreement_pickup_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz,p_start_mileage integer default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_user uuid; v_agreement public.rental_pricing_agreements%rowtype; v_reservation public.reservations%rowtype; v_vehicle public.vehicles%rowtype;
 v_pay_type public.pay_type_rules%rowtype; v_started jsonb; v_billing_result jsonb; v_vehicle_event uuid; v_contract_period uuid; v_line_id uuid; v_preview jsonb; v_rate_amount numeric;
 v_current_vehicle_id uuid; v_existing_line uuid;
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
 v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,clock_timestamp());
  if v_preview->>'status'<>'billing_preview_ready' then raise exception 'Activated pickup could not be loaded by Billing' using errcode='P0001'; end if;
 return jsonb_build_object('status','pricing_agreement_pickup_activated','reservation_id',v_reservation.id,'transportation_event_id',v_reservation.transportation_event_id,'vehicle_id',p_vehicle_id,'vehicle_event_id',v_vehicle_event,'contract_period_id',v_contract_period,'pricing_agreement_id',v_agreement.id,'billing_line_id',v_line_id,'rate_plan','daily','rate_amount',v_rate_amount::text,'actual_out_at',p_actual_out_at,'pricing_started_at',v_reservation.start_date,'billing_preview',v_preview);
end;$function$;

CREATE OR REPLACE FUNCTION public.get_billing_workspace_state(p_effective_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_actor_user_id uuid;
    v_case record;
    v_preview jsonb;
    v_operational jsonb;
    v_item jsonb;
    v_items jsonb := '[]'::jsonb;
    v_case_count integer := 0;
    v_ready_count integer := 0;
    v_attention_count integer := 0;
    v_accumulated_subtotal numeric := 0;
    v_accumulated_tax numeric := 0;
    v_accumulated_total numeric := 0;
BEGIN
    IF p_effective_at IS NULL THEN
        RAISE EXCEPTION 'Workspace timestamp is required'
            USING ERRCODE = '22023';
    END IF;

    SELECT app_user.id
    INTO v_actor_user_id
    FROM public.app_users app_user
    WHERE app_user.auth_user_id = auth.uid()
      AND app_user.is_active = true;

    IF v_actor_user_id IS NULL THEN
        RAISE EXCEPTION 'An active application user is required'
            USING ERRCODE = '42501';
    END IF;

    FOR v_case IN
        SELECT
            event.id AS transportation_event_id,
            event.status AS transportation_event_status,
            event.source_type,
            event.source_id,
            event.expected_return_at,
            event.created_at AS transportation_event_created_at,
            reservation.id AS reservation_id,
            reservation.status AS reservation_status,
            reservation.reservation_type,
            reservation.ro_number,
            reservation.requested_model,
            reservation.pay_type AS reservation_pay_type,
            reservation.start_date,
            reservation.expected_return_datetime,
            reservation.actual_return_datetime,
            reservation.billed_through_datetime,
            customer.id AS customer_id,
            customer.tekion_customer_number,
            customer.name AS customer_name,
            customer.phone AS customer_phone,
            customer.email AS customer_email,
            vehicle_event.id AS vehicle_event_id,
            vehicle_event.vehicle_id,
            vehicle_event.actual_out_at,
            vehicle_event.actual_in_at,
            vehicle.id AS resolved_vehicle_id,
            vehicle.vin,
            vehicle.vin_last8,
            vehicle.stock_number,
            vehicle.model_year,
            vehicle.model,
            vehicle.trim,
            vehicle.fleet_type,
            vehicle.current_tag
        FROM public.transportation_events event
        LEFT JOIN LATERAL (
            SELECT reservation.*
            FROM public.reservations reservation
            WHERE reservation.transportation_event_id = event.id
            ORDER BY reservation.created_at, reservation.id
            LIMIT 1
        ) reservation ON true
        LEFT JOIN public.customers customer
          ON customer.id =
             coalesce(reservation.customer_id, event.customer_id)
        LEFT JOIN LATERAL (
            SELECT vehicle_event.*
            FROM public.vehicle_events vehicle_event
            WHERE vehicle_event.transportation_event_id = event.id
              AND vehicle_event.is_open = true
            ORDER BY vehicle_event.actual_out_at DESC,
                     vehicle_event.id DESC
            LIMIT 1
        ) vehicle_event ON true
        LEFT JOIN public.vehicles vehicle
          ON vehicle.id = vehicle_event.vehicle_id
        WHERE lower(btrim(event.status)) = 'active'
        ORDER BY
            coalesce(
                event.expected_return_at,
                reservation.expected_return_datetime
            ) ASC NULLS LAST,
            vehicle_event.actual_out_at ASC NULLS LAST,
            event.created_at,
            event.id
    LOOP
        v_operational := public.get_transportation_event_operational_payload_state(v_case.transportation_event_id);
        IF jsonb_array_length(coalesce(v_operational -> 'current_continuity','[]'::jsonb)) = 0
           AND jsonb_array_length(coalesce(v_operational -> 'current_billing_lines','[]'::jsonb)) = 0 THEN
            CONTINUE;
        END IF;

        v_case_count := v_case_count + 1;

        BEGIN
            v_preview :=
                public.get_billing_preview_state(
                    v_case.transportation_event_id,
                    p_effective_at
                );
        EXCEPTION
            WHEN OTHERS THEN
                v_preview := jsonb_build_object(
                    'status', 'billing_preview_unavailable',
                    'transportation_event_id',
                        v_case.transportation_event_id,
                    'effective_at', p_effective_at
                );
        END;

        IF v_preview ->> 'status' = 'billing_preview_ready' THEN
            v_ready_count := v_ready_count + 1;
            v_accumulated_subtotal :=
                v_accumulated_subtotal
                + (v_preview ->> 'accumulated_subtotal')::numeric;
            v_accumulated_tax :=
                v_accumulated_tax
                + (v_preview ->> 'accumulated_tax')::numeric;
            v_accumulated_total :=
                v_accumulated_total
                + (v_preview ->> 'accumulated_total')::numeric;
        ELSE
            v_attention_count := v_attention_count + 1;
        END IF;

        v_item := jsonb_build_object(
            'transportation_event_id',
                v_case.transportation_event_id,
            'transportation_event_status',
                v_case.transportation_event_status,
            'source_type', v_case.source_type,
            'source_id', v_case.source_id,
            'expected_return_at',
                coalesce(
                    v_case.expected_return_at,
                    v_case.expected_return_datetime
                ),
            'reservation', jsonb_build_object(
                'reservation_id', v_case.reservation_id,
                'status', v_case.reservation_status,
                'reservation_type', v_case.reservation_type,
                'ro_number', v_case.ro_number,
                'requested_model', v_case.requested_model,
                'pay_type', v_case.reservation_pay_type,
                'start_date', v_case.start_date,
                'expected_return_datetime',
                    v_case.expected_return_datetime,
                'actual_return_datetime',
                    v_case.actual_return_datetime,
                'billed_through_datetime',
                    v_case.billed_through_datetime
            ),
            'customer', jsonb_build_object(
                'customer_id', v_case.customer_id,
                'tekion_customer_number',
                    v_case.tekion_customer_number,
                'name', v_case.customer_name,
                'phone', v_case.customer_phone,
                'email', v_case.customer_email
            ),
            'current_vehicle', jsonb_build_object(
                'vehicle_event_id', v_case.vehicle_event_id,
                'vehicle_id',
                    coalesce(
                        v_case.resolved_vehicle_id,
                        v_case.vehicle_id
                    ),
                'vin', v_case.vin,
                'vin_last8', v_case.vin_last8,
                'stock_number', v_case.stock_number,
                'model_year', v_case.model_year,
                'model', v_case.model,
                'trim', v_case.trim,
                'fleet_type', v_case.fleet_type,
                'current_tag', v_case.current_tag,
                'actual_out_at', v_case.actual_out_at,
                'actual_in_at', v_case.actual_in_at,
                'current_vehicle_contract_day',
                    CASE
                        WHEN v_case.actual_out_at IS NULL
                            THEN NULL
                        ELSE public.business_contract_days(
                            v_case.actual_out_at,
                            least(
                                p_effective_at,
                                coalesce(
                                    v_case.actual_in_at,
                                    p_effective_at
                                )
                            )
                        )
                    END
            ),
            'preview', v_preview
        );

        v_items := v_items || jsonb_build_array(v_item);
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'billing_workspace_ready',
        'effective_at', p_effective_at,
        'case_count', v_case_count,
        'ready_count', v_ready_count,
        'attention_count', v_attention_count,
        'accumulated_subtotal',
            v_accumulated_subtotal::text,
        'accumulated_tax',
            v_accumulated_tax::text,
        'accumulated_total',
            v_accumulated_total::text,
        'items', v_items
    );
END;
$function$;

alter function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) owner to postgres;
revoke all on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) from public,anon;
grant execute on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) to authenticated,service_role;
alter function public.get_billing_workspace_state(timestamptz) owner to postgres;
revoke all on function public.get_billing_workspace_state(timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.get_billing_workspace_state(timestamptz) to authenticated;
