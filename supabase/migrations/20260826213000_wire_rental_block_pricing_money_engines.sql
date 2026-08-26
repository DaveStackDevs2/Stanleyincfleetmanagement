-- Correction: wire A1 Rental block pricing into the existing authoritative money engines.
-- Data-free. Existing Loaner, Customer Pay, EW, lifecycle, and late-rule paths remain intact.
CREATE OR REPLACE FUNCTION public.get_billing_preview_state(p_transportation_event_id uuid, p_effective_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_actor_user_id uuid;
    v_event public.transportation_events%ROWTYPE;
    v_reservation public.reservations%ROWTYPE;
    v_vehicle_event public.vehicle_events%ROWTYPE;
    v_contract_period public.contract_periods%ROWTYPE;
    v_current_line public.billing_lines%ROWTYPE;
    v_pay_type_rule public.pay_type_rules%ROWTYPE;
    v_customer public.customers%ROWTYPE;
    v_vehicle public.vehicles%ROWTYPE;
    v_pay_type text;
    v_billing_start timestamptz;
    v_preview_end timestamptz;
    v_contract_days integer;
    v_rental_pricing_days integer;
    v_daily_rate numeric;
    v_rate_source text;
    v_rate_state jsonb;
    v_tax_state jsonb;
    v_tax_rate numeric;
    v_tax_amount numeric;
    v_tax_rate_source text;
    v_tax_explanation text;
    v_is_taxable boolean;
    v_subtotal numeric;
    v_total numeric;
    v_historical_subtotal numeric;
    v_historical_tax numeric;
    v_accumulated_subtotal numeric;
    v_accumulated_tax numeric;
    v_accumulated_total numeric;
    v_segments jsonb;
    v_extended_warranty jsonb;
    v_agreement public.rental_pricing_agreements%ROWTYPE;
    v_block_price jsonb;
    v_is_rental boolean;
BEGIN
    IF p_transportation_event_id IS NULL OR p_effective_at IS NULL THEN
        RAISE EXCEPTION
            'Transportation event and preview timestamp are required'
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

    SELECT event.*
    INTO v_event
    FROM public.transportation_events event
    WHERE event.id = p_transportation_event_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transportation event was not found'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT reservation.*
    INTO v_reservation
    FROM public.reservations reservation
    WHERE reservation.transportation_event_id =
        p_transportation_event_id
    ORDER BY reservation.created_at, reservation.id
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_dependency',
            'transportation_event_id', p_transportation_event_id,
            'effective_at', p_effective_at,
            'missing_dependency', 'reservation'
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.reservations reservation
        WHERE reservation.transportation_event_id =
            p_transportation_event_id
          AND reservation.id <> v_reservation.id
    ) THEN
        RAISE EXCEPTION
            'Transportation event has multiple reservations'
            USING ERRCODE = '21000';
    END IF;


    -- VERIFIED CLOSED BILLING SNAPSHOT BRANCH. Keep before open/current continuity assumptions.
    IF lower(btrim(v_event.status)) = 'closed' THEN
        IF v_event.closed_at IS NOT NULL AND p_effective_at < v_event.closed_at THEN
            RAISE EXCEPTION 'Closed billing preview timestamp must be at or after case closure'
                USING ERRCODE = '22023';
        END IF;

        SELECT line.* INTO v_current_line
        FROM public.billing_lines line
        WHERE line.transportation_event_id = p_transportation_event_id
          AND line.parent_billing_line_id IS NULL
        ORDER BY coalesce(line.end_time, line.paid_through_at, line.start_time) DESC NULLS LAST,
                 line.created_at DESC, line.id DESC
        LIMIT 1;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at,'missing_dependency','billing_history');
        END IF;

        IF EXISTS (SELECT 1 FROM public.billing_lines line WHERE line.transportation_event_id=p_transportation_event_id AND line.is_open) THEN
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at,'missing_dependency','closed_case_has_open_billing');
        END IF;
        IF EXISTS (
                SELECT 1 FROM public.billing_lines parent
                LEFT JOIN LATERAL (SELECT count(*) AS child_count, coalesce(sum(tax.amount),0) AS child_tax FROM public.billing_lines tax WHERE tax.parent_billing_line_id=parent.id AND tax.line_type='tax') stored_tax ON true
                WHERE parent.transportation_event_id=p_transportation_event_id AND parent.parent_billing_line_id IS NULL
                  AND (stored_tax.child_count > 1 OR stored_tax.child_tax <> coalesce(parent.tax_amount,0))
           ) THEN
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at,'missing_dependency','historical_tax_line_mismatch');
        END IF;

        SELECT vehicle_event.* INTO v_vehicle_event FROM public.vehicle_events vehicle_event
        WHERE vehicle_event.id=v_current_line.vehicle_event_id
        LIMIT 1;
        IF NOT FOUND THEN
            SELECT vehicle_event.* INTO v_vehicle_event FROM public.vehicle_events vehicle_event
            WHERE vehicle_event.transportation_event_id=p_transportation_event_id
            ORDER BY vehicle_event.actual_in_at DESC NULLS LAST, vehicle_event.actual_out_at DESC NULLS LAST, vehicle_event.id DESC LIMIT 1;
        END IF;
        IF v_vehicle_event.id IS NULL OR v_vehicle_event.actual_out_at IS NULL THEN
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at,'missing_dependency','historical_vehicle_assignment');
        END IF;

        SELECT contract_period.* INTO v_contract_period FROM public.contract_periods contract_period
        WHERE contract_period.id=v_current_line.contract_period_id LIMIT 1;
        IF NOT FOUND THEN
            SELECT contract_period.* INTO v_contract_period FROM public.contract_periods contract_period
            WHERE contract_period.vehicle_event_id=v_vehicle_event.id
            ORDER BY contract_period.renewal_sequence DESC, contract_period.contract_in_at DESC NULLS LAST, contract_period.contract_out_at DESC, contract_period.id DESC LIMIT 1;
        END IF;
        IF v_contract_period.id IS NULL OR v_contract_period.contract_out_at IS NULL THEN
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'vehicle_event_id',v_vehicle_event.id,'effective_at',p_effective_at,'missing_dependency','historical_contract_period');
        END IF;

        SELECT customer.* INTO v_customer FROM public.customers customer WHERE customer.id=coalesce(v_reservation.customer_id,v_event.customer_id);
        SELECT vehicle.* INTO v_vehicle FROM public.vehicles vehicle WHERE vehicle.id=coalesce(v_current_line.vehicle_id,v_vehicle_event.vehicle_id);

        SELECT min(parent.start_time), max(coalesce(parent.end_time,parent.paid_through_at,v_vehicle_event.actual_in_at,v_event.closed_at)),
               coalesce(sum(parent.amount),0), coalesce(sum(parent.tax_amount),0)
        INTO v_billing_start,v_preview_end,v_accumulated_subtotal,v_accumulated_tax
        FROM public.billing_lines parent
        WHERE parent.transportation_event_id=p_transportation_event_id AND parent.parent_billing_line_id IS NULL;
        v_accumulated_total := v_accumulated_subtotal + v_accumulated_tax;

        SELECT coalesce(jsonb_agg(jsonb_build_object(
            'billing_line_id',parent.id,'vehicle_id',parent.vehicle_id,'vehicle_event_id',parent.vehicle_event_id,
            'contract_period_id',parent.contract_period_id,'pay_type_rule_id',parent.pay_type_rule_id,'pay_type',parent.pay_type,
            'line_type',parent.line_type,'source_rule',parent.source_rule,'start_time',parent.start_time,'end_time',parent.end_time,
            'paid_through_at',parent.paid_through_at,'contract_days',CASE WHEN parent.start_time IS NULL THEN NULL WHEN parent.line_type = 'rental_extension' AND parent.extended_from_billing_line_id IS NOT NULL THEN greatest(0,public.business_contract_days(v_reservation.start_date,coalesce(parent.end_time,parent.paid_through_at,v_event.closed_at,p_effective_at))-public.business_contract_days(v_reservation.start_date,parent.start_time)) ELSE public.business_contract_days(parent.start_time,coalesce(parent.end_time,parent.paid_through_at,v_event.closed_at,p_effective_at)) END,
            'is_open',parent.is_open,'amount',parent.amount::text,'tax_amount',parent.tax_amount::text,
            'tax_billing_line_id',tax.id,'tax_line_amount',tax.amount::text,'daily_rate_override',parent.daily_rate_override::text,
            'default_daily_rate_snapshot',parent.default_daily_rate_snapshot::text,'tax_rate_snapshot',parent.tax_rate_snapshot::text,
            'is_taxable_snapshot',parent.is_taxable_snapshot,'tax_rate_source_snapshot',parent.tax_rate_source_snapshot,
            'warranty_provider_id',parent.warranty_provider_id,'default_covered_days_snapshot',parent.default_covered_days_snapshot,
            'covered_days_override',parent.covered_days_override,'extended_from_billing_line_id',parent.extended_from_billing_line_id
        ) ORDER BY parent.start_time,parent.created_at,parent.id),'[]'::jsonb)
        INTO v_segments FROM public.billing_lines parent
        LEFT JOIN public.billing_lines tax ON tax.parent_billing_line_id=parent.id AND tax.line_type='tax'
        WHERE parent.transportation_event_id=p_transportation_event_id AND parent.parent_billing_line_id IS NULL;

        SELECT jsonb_build_object('case_id',w.id,'provider_id',w.provider_id,'provider_name',w.provider_name,
          'default_covered_days_snapshot',w.default_covered_days_snapshot,'approved_days',w.approved_days,
          'effective_covered_days',coalesce(w.approved_days,w.default_covered_days_snapshot),'default_daily_rate_snapshot',w.default_daily_rate_snapshot::text,
          'coverage_started_at',w.coverage_started_at,'coverage_exhausted_at',w.coverage_exhausted_at,'current_contract_day',w.current_day_count,
          'post_coverage_pay_type_rule_id',w.post_coverage_pay_type_rule_id,'requires_manual_review',w.requires_manual_review,
          'can_override',EXISTS(SELECT 1 FROM public.v_user_effective_permissions permission WHERE permission.user_id=v_actor_user_id AND permission.permission_key='billing.extended_warranty_override'))
        INTO v_extended_warranty FROM public.warranty_cases w WHERE w.transportation_event_id=p_transportation_event_id;

        v_pay_type := coalesce(v_current_line.pay_type, v_reservation.pay_type);
        v_daily_rate := coalesce(v_current_line.daily_rate_override, v_current_line.default_daily_rate_snapshot, v_current_line.rate_amount_snapshot);
        v_tax_rate := v_current_line.tax_rate_snapshot;
        v_is_taxable := v_current_line.is_taxable_snapshot;
        IF v_current_line.pay_type_rule_id IS NULL OR v_pay_type IS NULL OR v_daily_rate IS NULL
           OR v_is_taxable IS NULL OR v_tax_rate IS NULL OR v_current_line.amount IS NULL
           OR v_current_line.tax_amount IS NULL THEN
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at,'missing_dependency','historical_billing_snapshot');
        END IF;
        v_subtotal := v_current_line.amount;
        v_tax_amount := v_current_line.tax_amount;
        v_total := v_subtotal + v_tax_amount;
        v_contract_days := public.business_contract_days(v_billing_start,v_preview_end);
        RETURN jsonb_build_object(
          'status','billing_preview_ready','transportation_event_id',p_transportation_event_id,'transportation_event_status',v_event.status,
          'reservation_id',v_reservation.id,'reservation_status',v_reservation.status,'reservation_type',v_reservation.reservation_type,
          'customer',jsonb_build_object('customer_id',v_customer.id,'tekion_customer_number',v_customer.tekion_customer_number,'name',v_customer.name,'phone',v_customer.phone,'email',v_customer.email),
          'vehicle',jsonb_build_object('vehicle_id',v_vehicle.id,'vin',v_vehicle.vin,'vin_last8',v_vehicle.vin_last8,'stock_number',v_vehicle.stock_number,'model_year',v_vehicle.model_year,'model',v_vehicle.model,'trim',v_vehicle.trim,'fleet_type',v_vehicle.fleet_type,'current_tag',v_vehicle.current_tag),
          'vehicle_event_id',v_vehicle_event.id,'contract_period_id',v_contract_period.id,'vehicle_out_at',v_vehicle_event.actual_out_at,
          'contract_out_at',v_contract_period.contract_out_at,'expected_return_at',coalesce(v_event.expected_return_at,v_reservation.expected_return_datetime),
          'actual_return_at',coalesce(v_vehicle_event.actual_in_at,v_reservation.actual_return_datetime,v_event.closed_at),
          'billed_through_at',coalesce(v_current_line.paid_through_at,v_reservation.billed_through_datetime),'current_billing_line_id',NULL,
          'line_type',v_current_line.line_type,'pay_type_rule_id',v_current_line.pay_type_rule_id,'pay_type',v_pay_type,
          'vehicle_class',v_reservation.requested_model,'billing_start',v_billing_start,'preview_end',v_preview_end,'effective_at',p_effective_at,
          'contract_days',v_contract_days,'daily_rate',v_daily_rate::text,'rate_source','stored_closed_billing_snapshot',
          'subtotal',v_subtotal::text,'is_taxable',v_is_taxable,'tax_rate',v_tax_rate::text,'tax_amount',v_tax_amount::text,
          'tax_rate_source',v_current_line.tax_rate_source_snapshot,'tax_explanation','Closed billing uses stored historical line snapshots without recalculation.',
          'total',v_total::text,'historical_subtotal',v_accumulated_subtotal::text,'historical_tax',v_accumulated_tax::text,
          'accumulated_subtotal',v_accumulated_subtotal::text,'accumulated_tax',v_accumulated_tax::text,'accumulated_total',v_accumulated_total::text,
          'segments',v_segments,'extended_warranty',v_extended_warranty);
    END IF;

    IF (
        SELECT count(*)
        FROM public.vehicle_events vehicle_event
        WHERE vehicle_event.transportation_event_id =
            p_transportation_event_id
          AND vehicle_event.is_open = true
    ) > 1 THEN
        RAISE EXCEPTION
            'Transportation event has multiple open vehicle assignments'
            USING ERRCODE = '21000';
    END IF;

    SELECT vehicle_event.*
    INTO v_vehicle_event
    FROM public.vehicle_events vehicle_event
    WHERE vehicle_event.transportation_event_id =
        p_transportation_event_id
      AND vehicle_event.is_open = true
    ORDER BY vehicle_event.actual_out_at DESC, vehicle_event.id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_dependency',
            'transportation_event_id', p_transportation_event_id,
            'reservation_id', v_reservation.id,
            'effective_at', p_effective_at,
            'missing_dependency', 'current_vehicle_assignment'
        );
    END IF;

    IF (
        SELECT count(*)
        FROM public.contract_periods contract_period
        WHERE contract_period.vehicle_event_id = v_vehicle_event.id
          AND contract_period.is_open = true
    ) > 1 THEN
        RAISE EXCEPTION
            'Vehicle assignment has multiple open contract periods'
            USING ERRCODE = '21000';
    END IF;

    SELECT contract_period.*
    INTO v_contract_period
    FROM public.contract_periods contract_period
    WHERE contract_period.vehicle_event_id = v_vehicle_event.id
      AND contract_period.is_open = true
    ORDER BY contract_period.renewal_sequence DESC,
             contract_period.contract_out_at DESC,
             contract_period.id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_dependency',
            'transportation_event_id', p_transportation_event_id,
            'reservation_id', v_reservation.id,
            'vehicle_event_id', v_vehicle_event.id,
            'effective_at', p_effective_at,
            'missing_dependency', 'current_contract_period'
        );
    END IF;

    SELECT line.*
    INTO v_current_line
    FROM public.billing_lines line
    WHERE line.transportation_event_id =
        p_transportation_event_id
      AND line.parent_billing_line_id IS NULL
      AND line.is_open = true
    ORDER BY line.start_time DESC NULLS LAST,
             line.created_at DESC,
             line.id DESC
    LIMIT 1;

    v_pay_type := coalesce(
        nullif(btrim(v_current_line.pay_type), ''),
        nullif(btrim(v_reservation.pay_type), '')
    );

    IF v_pay_type IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_dependency',
            'transportation_event_id', p_transportation_event_id,
            'reservation_id', v_reservation.id,
            'vehicle_event_id', v_vehicle_event.id,
            'contract_period_id', v_contract_period.id,
            'effective_at', p_effective_at,
            'missing_dependency', 'pay_type'
        );
    END IF;

    IF v_current_line.pay_type_rule_id IS NOT NULL THEN
        SELECT rule.*
        INTO v_pay_type_rule
        FROM public.pay_type_rules rule
        WHERE rule.id = v_current_line.pay_type_rule_id;
    ELSE
        SELECT rule.*
        INTO v_pay_type_rule
        FROM public.pay_type_rules rule
        WHERE lower(btrim(rule.pay_type)) =
              lower(v_pay_type)
          AND rule.is_active = true
          AND coalesce(rule.active, false) = true
        ORDER BY rule.sort_order, rule.id
        LIMIT 1;
    END IF;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_configuration',
            'transportation_event_id', p_transportation_event_id,
            'reservation_id', v_reservation.id,
            'vehicle_event_id', v_vehicle_event.id,
            'contract_period_id', v_contract_period.id,
            'pay_type', v_pay_type,
            'effective_at', p_effective_at,
            'missing_configuration', 'pay_type_rule'
        );
    END IF;

    IF v_current_line.id IS NULL
       AND NOT (
           v_pay_type_rule.is_active
           AND coalesce(v_pay_type_rule.active, false)
       ) THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_configuration',
            'transportation_event_id', p_transportation_event_id,
            'reservation_id', v_reservation.id,
            'vehicle_event_id', v_vehicle_event.id,
            'contract_period_id', v_contract_period.id,
            'pay_type_rule_id', v_pay_type_rule.id,
            'pay_type', v_pay_type_rule.pay_type,
            'effective_at', p_effective_at,
            'missing_configuration', 'enabled_pay_type'
        );
    END IF;

    v_billing_start := coalesce(
        v_current_line.start_time,
        v_contract_period.contract_out_at,
        v_vehicle_event.actual_out_at
    );

    v_preview_end := least(
        p_effective_at,
        coalesce(v_vehicle_event.actual_in_at, p_effective_at),
        coalesce(v_event.closed_at, p_effective_at)
    );

    IF v_billing_start IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_dependency',
            'transportation_event_id', p_transportation_event_id,
            'reservation_id', v_reservation.id,
            'vehicle_event_id', v_vehicle_event.id,
            'contract_period_id', v_contract_period.id,
            'effective_at', p_effective_at,
            'missing_dependency', 'billing_start'
        );
    END IF;

    v_is_rental := lower(btrim(coalesce(v_reservation.reservation_type, ''))) = 'rental';
    IF v_preview_end < v_billing_start THEN
        IF v_current_line.line_type = 'rental_extension' AND v_current_line.extended_from_billing_line_id IS NOT NULL THEN
            -- A valid future-start Extension has zero elapsed Extension days.
            v_preview_end := v_billing_start;
        ELSE
            RAISE EXCEPTION
                'Preview timestamp precedes the current billing segment'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    v_contract_days := CASE
        WHEN v_current_line.line_type = 'rental_extension'
         AND v_current_line.extended_from_billing_line_id IS NOT NULL
        THEN greatest(0, public.business_contract_days(v_reservation.start_date,v_preview_end)-public.business_contract_days(v_reservation.start_date,v_billing_start))
        ELSE public.business_contract_days(v_billing_start,v_preview_end)
    END;
    IF v_is_rental THEN
        v_rental_pricing_days := public.rental_pricing_days(v_billing_start,v_preview_end);
    END IF;

    IF v_current_line.daily_rate_override IS NOT NULL THEN
        v_daily_rate := v_current_line.daily_rate_override;
        v_rate_source := 'billing_line_daily_rate_override';
    ELSIF v_current_line.default_daily_rate_snapshot IS NOT NULL THEN
        v_daily_rate := v_current_line.default_daily_rate_snapshot;
        v_rate_source := 'billing_line_daily_rate_snapshot';
    ELSE
        v_rate_state :=
            public.resolve_rental_daily_rate_state(
                v_reservation.requested_model,
                v_pay_type_rule.id,
                v_billing_start
            );

        IF v_rate_state ->> 'status' =
           'rental_daily_rate_resolved' THEN
            v_daily_rate :=
                (v_rate_state ->> 'daily_rate')::numeric;
            v_rate_source := 'rental_rate_rule';
        ELSIF v_pay_type_rule.default_daily_amount IS NOT NULL THEN
            v_daily_rate :=
                v_pay_type_rule.default_daily_amount;
            v_rate_source := 'pay_type_default_daily_amount';
        END IF;
    END IF;

    SELECT customer.*
    INTO v_customer
    FROM public.customers customer
    WHERE customer.id =
        coalesce(v_reservation.customer_id, v_event.customer_id);

    SELECT vehicle.*
    INTO v_vehicle
    FROM public.vehicles vehicle
    WHERE vehicle.id = v_vehicle_event.vehicle_id;

    SELECT coalesce(
        jsonb_agg(
            jsonb_build_object(
                'billing_line_id', parent.id,
                'vehicle_id', parent.vehicle_id,
                'vehicle_event_id', parent.vehicle_event_id,
                'contract_period_id', parent.contract_period_id,
                'pay_type_rule_id', parent.pay_type_rule_id,
                'pay_type', parent.pay_type,
                'line_type', parent.line_type,
                'source_rule', parent.source_rule,
                'start_time', parent.start_time,
                'end_time', parent.end_time,
                'paid_through_at', parent.paid_through_at,
                'contract_days', CASE WHEN parent.start_time IS NULL THEN NULL WHEN parent.line_type = 'rental_extension' AND parent.extended_from_billing_line_id IS NOT NULL THEN greatest(0,public.business_contract_days(v_reservation.start_date,coalesce(parent.end_time,parent.paid_through_at,p_effective_at))-public.business_contract_days(v_reservation.start_date,parent.start_time)) ELSE public.business_contract_days(parent.start_time,coalesce(parent.end_time,parent.paid_through_at,p_effective_at)) END,
                'is_open', parent.is_open,
                'amount', parent.amount::text,
                'tax_amount', parent.tax_amount::text,
                'tax_billing_line_id', tax.id,
                'tax_line_amount', tax.amount::text,
                'daily_rate_override',
                    parent.daily_rate_override::text,
                'default_daily_rate_snapshot',
                    parent.default_daily_rate_snapshot::text,
                'tax_rate_snapshot',
                    parent.tax_rate_snapshot::text,
                'is_taxable_snapshot',
                    parent.is_taxable_snapshot,
                'tax_rate_source_snapshot',
                    parent.tax_rate_source_snapshot,
                'warranty_provider_id',
                    parent.warranty_provider_id,
                'default_covered_days_snapshot',
                    parent.default_covered_days_snapshot,
                'covered_days_override',
                    parent.covered_days_override,
                'extended_from_billing_line_id',
                    parent.extended_from_billing_line_id
            )
            ORDER BY parent.start_time,
                     parent.created_at,
                     parent.id
        ),
        '[]'::jsonb
    )
    INTO v_segments
    FROM public.billing_lines parent
    LEFT JOIN public.billing_lines tax
      ON tax.parent_billing_line_id = parent.id
     AND tax.line_type = 'tax'
    WHERE parent.transportation_event_id =
        p_transportation_event_id
      AND parent.parent_billing_line_id IS NULL;

    SELECT coalesce(sum(line.amount), 0),
           coalesce(sum(line.tax_amount), 0)
    INTO v_historical_subtotal, v_historical_tax
    FROM public.billing_lines line
    WHERE line.transportation_event_id =
        p_transportation_event_id
      AND line.parent_billing_line_id IS NULL
      AND line.is_open = false;

    SELECT jsonb_build_object(
        'case_id', warranty_case.id,
        'provider_id', warranty_case.provider_id,
        'provider_name', warranty_case.provider_name,
        'default_covered_days_snapshot',
            warranty_case.default_covered_days_snapshot,
        'approved_days', warranty_case.approved_days,
        'effective_covered_days',
            coalesce(
                warranty_case.approved_days,
                warranty_case.default_covered_days_snapshot
            ),
        'default_daily_rate_snapshot',
            warranty_case.default_daily_rate_snapshot::text,
        'coverage_started_at',
            warranty_case.coverage_started_at,
        'coverage_exhausted_at',
            warranty_case.coverage_exhausted_at,
        'current_contract_day',
            warranty_case.current_day_count,
        'post_coverage_pay_type_rule_id',
            warranty_case.post_coverage_pay_type_rule_id,
        'requires_manual_review',
            warranty_case.requires_manual_review,
        'can_override',
            EXISTS (
                SELECT 1
                FROM public.v_user_effective_permissions permission
                WHERE permission.user_id = v_actor_user_id
                  AND permission.permission_key =
                      'billing.extended_warranty_override'
            )
    )
    INTO v_extended_warranty
    FROM public.warranty_cases warranty_case
    WHERE warranty_case.transportation_event_id =
        p_transportation_event_id;

    IF v_daily_rate IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'billing_preview_missing_configuration',
            'transportation_event_id', p_transportation_event_id,
            'reservation_id', v_reservation.id,
            'customer_id',
                coalesce(v_reservation.customer_id, v_event.customer_id),
            'vehicle_id', v_vehicle_event.vehicle_id,
            'vehicle_event_id', v_vehicle_event.id,
            'contract_period_id', v_contract_period.id,
            'pay_type_rule_id', v_pay_type_rule.id,
            'pay_type', v_pay_type_rule.pay_type,
            'vehicle_class', v_reservation.requested_model,
            'billing_start', v_billing_start,
            'preview_end', v_preview_end,
            'contract_days', v_contract_days,
            'effective_at', p_effective_at,
            'missing_configuration', 'daily_rate',
            'rate_resolution', v_rate_state,
            'segments', v_segments,
            'extended_warranty', v_extended_warranty
        );
    END IF;

    IF v_daily_rate < 0
       OR v_daily_rate::text IN ('NaN', 'Infinity', '-Infinity') THEN
        RAISE EXCEPTION
            'Resolved daily rate is invalid'
            USING ERRCODE = '22023';
    END IF;

    IF v_is_rental THEN
        SELECT agreement.* INTO v_agreement
        FROM public.rental_pricing_agreements agreement
        WHERE agreement.id = v_current_line.pricing_agreement_id
           OR (agreement.reservation_id = v_reservation.id AND agreement.is_active)
        ORDER BY (agreement.id = v_current_line.pricing_agreement_id) DESC, agreement.updated_at DESC
        LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'Rental pricing agreement snapshot is unavailable' USING ERRCODE='P0002'; END IF;
        v_block_price := public.resolve_rental_block_pricing_state(v_rental_pricing_days,v_agreement.daily_rate_snapshot,v_agreement.weekly_rate_snapshot,v_agreement.monthly_rate_snapshot);
        v_subtotal := (v_block_price->>'subtotal')::numeric;
        v_rate_source := 'rental_block_pricing_resolver';
    ELSE
        v_subtotal := v_daily_rate * v_contract_days;
    END IF;

    IF v_current_line.id IS NOT NULL THEN
        v_is_taxable := v_current_line.is_taxable_snapshot;
        v_tax_rate := v_current_line.tax_rate_snapshot;
        v_tax_rate_source :=
            v_current_line.tax_rate_source_snapshot;
        v_tax_amount :=
            CASE
                WHEN v_is_taxable
                    THEN v_subtotal * v_tax_rate
                ELSE 0
            END;
        v_tax_explanation :=
            'Tax uses the billing line historical snapshot without rounding.';
    ELSE
        v_tax_state :=
            public.resolve_billing_tax_state(
                v_pay_type_rule.pay_type,
                v_subtotal
            );
        v_is_taxable :=
            (v_tax_state ->> 'is_taxable')::boolean;
        v_tax_rate :=
            (v_tax_state ->> 'tax_rate')::numeric;
        v_tax_amount :=
            (v_tax_state ->> 'tax_amount')::numeric;
        v_tax_rate_source :=
            v_tax_state ->> 'tax_rate_source';
        v_tax_explanation :=
            v_tax_state ->> 'explanation';
    END IF;

    v_total := v_subtotal + v_tax_amount;
    v_accumulated_subtotal :=
        v_historical_subtotal + v_subtotal;
    v_accumulated_tax :=
        v_historical_tax + v_tax_amount;
    v_accumulated_total :=
        v_accumulated_subtotal + v_accumulated_tax;

    RETURN jsonb_build_object(
        'status', 'billing_preview_ready',
        'transportation_event_id', p_transportation_event_id,
        'transportation_event_status', v_event.status,
        'reservation_id', v_reservation.id,
        'reservation_status', v_reservation.status,
        'reservation_type', v_reservation.reservation_type,
        'customer', jsonb_build_object(
            'customer_id', v_customer.id,
            'tekion_customer_number',
                v_customer.tekion_customer_number,
            'name', v_customer.name,
            'phone', v_customer.phone,
            'email', v_customer.email
        ),
        'vehicle', jsonb_build_object(
            'vehicle_id', v_vehicle.id,
            'vin', v_vehicle.vin,
            'vin_last8', v_vehicle.vin_last8,
            'stock_number', v_vehicle.stock_number,
            'model_year', v_vehicle.model_year,
            'model', v_vehicle.model,
            'trim', v_vehicle.trim,
            'fleet_type', v_vehicle.fleet_type,
            'current_tag', v_vehicle.current_tag
        ),
        'vehicle_event_id', v_vehicle_event.id,
        'contract_period_id', v_contract_period.id,
        'vehicle_out_at', v_vehicle_event.actual_out_at,
        'contract_out_at', v_contract_period.contract_out_at,
        'expected_return_at',
            coalesce(
                v_event.expected_return_at,
                v_reservation.expected_return_datetime
            ),
        'actual_return_at',
            coalesce(
                v_vehicle_event.actual_in_at,
                v_reservation.actual_return_datetime,
                v_event.closed_at
            ),
        'billed_through_at',
            coalesce(
                v_current_line.paid_through_at,
                v_reservation.billed_through_datetime
            ),
        'current_billing_line_id', v_current_line.id,
        'line_type', v_current_line.line_type,
        'pay_type_rule_id', v_pay_type_rule.id,
        'pay_type', v_pay_type_rule.pay_type,
        'vehicle_class', v_reservation.requested_model,
        'billing_start', v_billing_start,
        'preview_end', v_preview_end,
        'effective_at', p_effective_at,
        'contract_days', v_contract_days,
        'daily_rate', v_daily_rate::text,
        'rate_source', v_rate_source,
        'rental_block_pricing', v_block_price,
        'subtotal', v_subtotal::text,
        'is_taxable', v_is_taxable,
        'tax_rate', v_tax_rate::text,
        'tax_amount', v_tax_amount::text,
        'tax_rate_source', v_tax_rate_source,
        'tax_explanation', v_tax_explanation,
        'total', v_total::text,
        'historical_subtotal', v_historical_subtotal::text,
        'historical_tax', v_historical_tax::text,
        'accumulated_subtotal',
            v_accumulated_subtotal::text,
        'accumulated_tax', v_accumulated_tax::text,
        'accumulated_total',
            v_accumulated_total::text,
        'segments', v_segments,
        'extended_warranty', v_extended_warranty
    );
END;
$function$;create or replace function public.activate_pricing_agreement_pickup_state(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz,p_start_mileage integer default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_user uuid; v_agreement public.rental_pricing_agreements%rowtype; v_reservation public.reservations%rowtype; v_vehicle public.vehicles%rowtype;
 v_pay_type public.pay_type_rules%rowtype; v_started jsonb; v_billing_result jsonb; v_vehicle_event uuid; v_contract_period uuid; v_line_id uuid; v_preview jsonb; v_rate_amount numeric;
 v_current_vehicle_id uuid; v_existing_line uuid; v_tax_sync jsonb; v_tax_count integer; v_tax_sum numeric; v_payment jsonb;
 v_block_price jsonb; v_block_tax jsonb; v_segment_days integer; v_reservation_type text;
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
  -- Rental plan metadata is compatibility-only; Loaner retains Daily compatibility.
  if v_reservation_type='loaner' and v_agreement.current_rate_plan<>'daily' then raise exception 'Customer Pay Loaner pricing supports only the Daily plan' using errcode='P0001'; end if;
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
  v_segment_days:=public.rental_pricing_days(v_reservation.start_date,v_reservation.expected_return_datetime);
  v_block_price:=public.resolve_rental_block_pricing_state(v_segment_days,v_agreement.daily_rate_snapshot,v_agreement.weekly_rate_snapshot,v_agreement.monthly_rate_snapshot);
  v_block_tax:=public.resolve_billing_tax_state(v_pay_type.pay_type,(v_block_price->>'subtotal')::numeric);
  update public.billing_lines set amount=(v_block_price->>'subtotal')::numeric,tax_amount=(v_block_tax->>'tax_amount')::numeric,end_time=v_reservation.expected_return_datetime,rental_block_pricing_snapshot=v_block_price where id=v_line_id;
  v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime);
  if v_preview->>'status'='billing_preview_ready' then
   v_tax_sync:=public.ensure_tax_child_line_state(v_line_id);
   select count(*),sum(amount) into v_tax_count,v_tax_sum from public.billing_lines where parent_billing_line_id=v_line_id and line_type='tax';
   if (((v_preview->>'tax_amount')::numeric>0 and (v_tax_count<>1 or v_tax_sum is distinct from (v_preview->>'tax_amount')::numeric)) or ((v_preview->>'tax_amount')::numeric=0 and v_tax_count<>0)) then raise exception 'Pickup tax child does not match authoritative tax'; end if;
   v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime);
  end if;
  v_payment:=public.get_rental_payment_state(v_reservation.transportation_event_id);
 else
  -- Loaners remain on the established inclusive Daily path and never call Rental money/payment resolvers.
  v_preview:=public.get_billing_preview_state(v_reservation.transportation_event_id,clock_timestamp());
  v_payment:=null;
 end if;
 if v_preview->>'status'<>'billing_preview_ready' then raise exception 'Activated pickup could not be loaded by Billing' using errcode='P0001'; end if;
 return jsonb_build_object('rental_payment_state',v_payment,'status','pricing_agreement_pickup_activated','reservation_type',v_reservation_type,'ro_number',v_reservation.ro_number,'reservation_id',v_reservation.id,'transportation_event_id',v_reservation.transportation_event_id,'vehicle_id',p_vehicle_id,'vehicle_event_id',v_vehicle_event,'contract_period_id',v_contract_period,'pricing_agreement_id',v_agreement.id,'billing_line_id',v_line_id,'rate_plan','daily','rate_amount',v_rate_amount::text,'actual_out_at',p_actual_out_at,'pricing_started_at',v_reservation.start_date,'billing_preview',v_preview);
end;$function$;
CREATE OR REPLACE FUNCTION public.accept_extension_commit_state(p_transportation_event_id uuid,p_current_billing_line_id uuid,p_new_expected_return_at timestamptz,p_extension_amount numeric,p_extension_tax_amount numeric DEFAULT NULL,p_reason_code text DEFAULT NULL,p_optional_note text DEFAULT NULL,p_entered_by_user_id uuid DEFAULT NULL,p_dependency_id_to_escalate uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE v_old_expected_return_at timestamptz; v_expected_return_result jsonb; v_note_result jsonb; v_close_result jsonb; v_extension_line_result jsonb; v_escalation_result jsonb:=NULL;
 v_line public.billing_lines%rowtype; v_reservation public.reservations%rowtype; v_agreement public.rental_pricing_agreements%rowtype;
 v_block_price jsonb; v_tax jsonb; v_server_amount numeric; v_server_tax numeric; v_new_line uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.transportation_events WHERE id=p_transportation_event_id) THEN RAISE EXCEPTION 'Transportation event does not exist'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.billing_lines WHERE id=p_current_billing_line_id AND is_open=true AND line_type IS DISTINCT FROM 'tax') THEN RAISE EXCEPTION 'Open current billing line does not exist'; END IF;
 IF p_reason_code IS NULL OR btrim(p_reason_code)='' THEN RAISE EXCEPTION 'Reason code is required for accepted extension'; END IF;
 IF p_extension_amount IS NULL OR p_extension_amount<0 OR (p_extension_tax_amount IS NOT NULL AND p_extension_tax_amount<0) THEN RAISE EXCEPTION 'Extension amounts must be non-negative'; END IF;
 IF p_entered_by_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.app_users WHERE id=p_entered_by_user_id) THEN RAISE EXCEPTION 'User does not exist'; END IF;
 IF p_dependency_id_to_escalate IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.reservation_vehicle_dependencies WHERE id=p_dependency_id_to_escalate) THEN RAISE EXCEPTION 'Dependency does not exist'; END IF;
 SELECT expected_return_at INTO v_old_expected_return_at FROM public.transportation_events WHERE id=p_transportation_event_id FOR UPDATE;
 IF v_old_expected_return_at IS NULL OR p_new_expected_return_at<=v_old_expected_return_at THEN RAISE EXCEPTION 'New expected return must be later'; END IF;
 SELECT * INTO v_line FROM public.billing_lines WHERE id=p_current_billing_line_id FOR UPDATE;
 SELECT * INTO v_reservation FROM public.reservations WHERE id=v_line.reservation_id FOR UPDATE;
 IF lower(btrim(coalesce(v_reservation.reservation_type,''))) = 'rental' THEN
   IF public.rental_pricing_days(v_reservation.start_date,p_new_expected_return_at)>56 THEN RAISE EXCEPTION 'Same-vehicle intended Rental period cannot exceed 56 contract days' USING ERRCODE='22023'; END IF;
   SELECT * INTO v_agreement FROM public.rental_pricing_agreements WHERE reservation_id=v_reservation.id AND is_active=true ORDER BY updated_at DESC LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'Active Rental pricing agreement was not found' USING ERRCODE='P0002'; END IF;
   v_block_price:=public.resolve_rental_block_pricing_state(public.rental_pricing_days(v_old_expected_return_at,p_new_expected_return_at),v_agreement.daily_rate_snapshot,v_agreement.weekly_rate_snapshot,v_agreement.monthly_rate_snapshot);
   v_tax:=public.resolve_billing_tax_state(coalesce(v_line.pay_type,v_reservation.pay_type),(v_block_price->>'subtotal')::numeric);
   v_server_amount:=(v_block_price->>'subtotal')::numeric; v_server_tax:=(v_tax->>'tax_amount')::numeric;
   -- Compatibility parameters are assertions only; caller money never becomes authoritative.
   IF p_extension_amount IS DISTINCT FROM v_server_amount OR coalesce(p_extension_tax_amount,0) IS DISTINCT FROM v_server_tax THEN RAISE EXCEPTION 'Submitted Rental Extension money does not match authoritative block pricing' USING ERRCODE='22023'; END IF;
 ELSE v_server_amount:=p_extension_amount; v_server_tax:=p_extension_tax_amount; END IF;
 v_expected_return_result:=public.set_expected_return_state(p_transportation_event_id,p_new_expected_return_at);
 v_note_result:=public.add_estimated_return_change_note_state(p_transportation_event_id,v_old_expected_return_at,p_new_expected_return_at,p_reason_code,p_optional_note,p_entered_by_user_id);
 v_close_result:=public.close_billing_line_state(p_current_billing_line_id,v_old_expected_return_at);
 v_extension_line_result:=public.create_extension_billing_line_state(p_current_billing_line_id,v_server_amount,v_server_tax,p_new_expected_return_at);
 IF v_block_price IS NOT NULL THEN
   v_new_line:=(v_extension_line_result->>'new_billing_line_id')::uuid;
   UPDATE public.billing_lines SET pricing_agreement_id=v_agreement.id,rate_plan_snapshot='daily',rate_amount_snapshot=v_agreement.daily_rate_snapshot,rental_block_pricing_snapshot=v_block_price WHERE id=v_new_line;
 END IF;
 IF p_dependency_id_to_escalate IS NOT NULL THEN v_escalation_result:=public.escalate_dependency_to_critical_state(p_dependency_id_to_escalate,p_entered_by_user_id); END IF;
 RETURN jsonb_build_object('status',CASE WHEN p_dependency_id_to_escalate IS NOT NULL THEN 'accepted_with_conflict_escalation' ELSE 'accepted' END,'transportation_event_id',p_transportation_event_id,'current_billing_line_id',p_current_billing_line_id,'expected_return_result',v_expected_return_result,'note_result',v_note_result,'close_result',v_close_result,'extension_line_result',v_extension_line_result,'dependency_escalation_result',v_escalation_result);
END $function$;

CREATE OR REPLACE FUNCTION public.complete_case_return_and_close_state(
    p_reservation_id uuid,
    p_actual_in_at timestamptz,
    p_end_mileage integer DEFAULT NULL,
    p_close_billing boolean DEFAULT true,
    p_close_note text DEFAULT NULL,
    p_closed_by uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $function$
DECLARE
    v_reservation record;
    v_candidate record;
    v_return_result jsonb := null;
    v_billing_close_result jsonb := null;
    v_transportation_close_result jsonb;
    v_current_billing_line public.billing_lines%ROWTYPE;
    v_final_preview jsonb;
    v_tax_child_result jsonb;
    v_tax_child_count integer;
    v_tax_child_amount numeric;
    v_final_subtotal numeric;
    v_final_tax numeric;
    v_agreement public.rental_pricing_agreements%ROWTYPE;
    v_block_price jsonb;
    v_tax_state jsonb;
    v_previous_charge numeric;
    v_previous_tax numeric;
    v_charge_delta numeric := 0;
    v_tax_delta numeric := 0;
    v_total_delta numeric := 0;
    v_difference_status text := 'no_difference';
BEGIN
    SELECT * INTO v_reservation
    FROM public.reservations
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;
    IF p_actual_in_at IS NULL THEN
        RAISE EXCEPTION 'actual_in_at cannot be null';
    END IF;
    IF p_actual_in_at < v_reservation.start_date THEN
        RAISE EXCEPTION 'actual_in_at % is before reservation start_date %', p_actual_in_at, v_reservation.start_date;
    END IF;
    IF p_end_mileage IS NOT NULL AND p_end_mileage < 0 THEN
        RAISE EXCEPTION 'end_mileage must be non-negative';
    END IF;
    IF p_closed_by IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.app_users WHERE id = p_closed_by
    ) THEN
        RAISE EXCEPTION 'User % does not exist', p_closed_by;
    END IF;

    SELECT * INTO v_candidate
    FROM public.v_case_completion_candidate_state
    WHERE reservation_id = p_reservation_id
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case completion candidate state not found for reservation %', p_reservation_id;
    END IF;

    -- Finalize the exact open parent while continuity, contract, and Billing are open.
    IF p_close_billing AND coalesce(v_candidate.has_open_billing_line, false) THEN
        IF v_candidate.parent_billing_line_id IS NULL THEN
            RAISE EXCEPTION 'Open billing candidate has no parent billing line';
        END IF;

        SELECT line.* INTO v_current_billing_line
        FROM public.billing_lines line
        WHERE line.id = v_candidate.parent_billing_line_id
        FOR UPDATE;

        IF NOT FOUND
           OR v_current_billing_line.reservation_id IS DISTINCT FROM p_reservation_id
           OR v_current_billing_line.transportation_event_id IS DISTINCT FROM v_reservation.transportation_event_id
           OR v_current_billing_line.parent_billing_line_id IS NOT NULL
           OR v_current_billing_line.line_type = 'tax'
           OR v_current_billing_line.is_open IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'Completion billing parent does not match the open case';
        END IF;

        v_final_preview := public.get_billing_preview_state(
            v_reservation.transportation_event_id,
            p_actual_in_at
        );
        IF v_final_preview->>'status' <> 'billing_preview_ready' THEN
            RAISE EXCEPTION 'Final billing preview is not ready';
        END IF;
        IF (v_final_preview->>'current_billing_line_id')::uuid IS DISTINCT FROM v_current_billing_line.id THEN
            RAISE EXCEPTION 'Final billing preview does not match the locked parent line';
        END IF;
        IF v_final_preview->>'subtotal' IS NULL OR v_final_preview->>'tax_amount' IS NULL THEN
            RAISE EXCEPTION 'Final billing preview is missing authoritative money';
        END IF;

        v_previous_charge := coalesce(v_current_billing_line.amount,0);
        v_previous_tax := coalesce(v_current_billing_line.tax_amount,0);
        -- Billing preview owns both Rental completed-day pricing and the open
        -- line's historical tax snapshots.  Return must not resolve current tax.
        v_final_subtotal := (v_final_preview->>'subtotal')::numeric;
        v_final_tax := (v_final_preview->>'tax_amount')::numeric;
        IF lower(coalesce(v_reservation.reservation_type,'')) LIKE '%rental%' THEN
            v_block_price := v_final_preview->'rental_block_pricing';
            IF v_block_price IS NULL OR v_block_price = 'null'::jsonb THEN
                RAISE EXCEPTION 'Final Rental billing preview is missing block pricing';
            END IF;
        END IF;
        v_charge_delta:=v_final_subtotal-v_previous_charge; v_tax_delta:=v_final_tax-v_previous_tax; v_total_delta:=v_charge_delta+v_tax_delta;
        v_difference_status:=CASE WHEN v_total_delta<0 THEN 'refund_due' WHEN v_total_delta>0 THEN 'customer_owes' ELSE 'no_difference' END;
        UPDATE public.billing_lines
        SET amount = v_final_subtotal, tax_amount = v_final_tax,
            rental_block_pricing_snapshot=coalesce(v_block_price,rental_block_pricing_snapshot), updated_at = now()
        WHERE id = v_current_billing_line.id;

        v_tax_child_result := public.ensure_tax_child_line_state(v_current_billing_line.id);
        SELECT count(*), sum(child.amount)
        INTO v_tax_child_count, v_tax_child_amount
        FROM public.billing_lines child
        WHERE child.parent_billing_line_id = v_current_billing_line.id
          AND child.line_type = 'tax';
        IF (v_final_tax > 0 AND (v_tax_child_count <> 1 OR v_tax_child_amount IS DISTINCT FROM v_final_tax))
           OR (v_final_tax = 0 AND v_tax_child_count <> 0) THEN
            RAISE EXCEPTION 'Final tax child does not match authoritative tax';
        END IF;
    END IF;

    IF coalesce(v_candidate.has_active_continuity, false) THEN
        v_return_result := public.return_reservation_vehicle_use_state(
            p_reservation_id, p_actual_in_at, p_end_mileage, p_close_note
        );
    ELSE
        v_return_result := public.set_reservation_actual_return_state(
            p_reservation_id, p_actual_in_at, p_end_mileage, p_close_note
        );
    END IF;

    IF p_close_billing AND coalesce(v_candidate.has_open_billing_line, false) THEN
        v_billing_close_result := public.close_current_reservation_billing_line_state(
            p_reservation_id, p_actual_in_at
        );
        IF (v_billing_close_result->>'parent_billing_line_id')::uuid IS DISTINCT FROM v_current_billing_line.id THEN
            RAISE EXCEPTION 'Closed billing parent does not match the finalized parent line';
        END IF;
    END IF;

    v_transportation_close_result := public.close_transportation_event_state(
        v_reservation.transportation_event_id, p_closed_by, p_actual_in_at, p_close_note
    );

    RETURN jsonb_build_object(
        'status', 'case_returned_and_closed',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'actual_in_at', p_actual_in_at,
        'difference_status', v_difference_status,
        'charge_delta', v_charge_delta::text,
        'tax_delta', v_tax_delta::text,
        'total_delta', v_total_delta::text,
        'refund_due', CASE WHEN v_total_delta<0 THEN (-v_total_delta)::text ELSE '0' END,
        'customer_owes', CASE WHEN v_total_delta>0 THEN v_total_delta::text ELSE '0' END,
        'no_difference', v_total_delta=0,
        'return_result', v_return_result,
        'billing_close_result', v_billing_close_result,
        'transportation_event_close_result', v_transportation_close_result
    );
END;
$function$;

-- Preserve the verified-live pg_proc and browser/service execution boundaries.
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SET search_path TO '';
REVOKE ALL ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) TO authenticated;

ALTER FUNCTION public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) OWNER TO postgres;
ALTER FUNCTION public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) SECURITY DEFINER;
ALTER FUNCTION public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) SET search_path TO '';
REVOKE ALL ON FUNCTION public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) TO authenticated,service_role;

ALTER FUNCTION public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) OWNER TO postgres;
ALTER FUNCTION public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) SECURITY INVOKER;
ALTER FUNCTION public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) RESET ALL;
REVOKE ALL ON FUNCTION public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) TO service_role;

ALTER FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) OWNER TO postgres;
ALTER FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) SECURITY INVOKER;
ALTER FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) RESET ALL;
REVOKE ALL ON FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) TO service_role;
