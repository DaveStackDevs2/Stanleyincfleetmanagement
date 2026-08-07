-- Operational Billing Dashboard contract already verified in live project ycwejunodgnnkickjvsk.
-- This migration records the exact live definitions and does not seed or rewrite operational data.

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

    IF coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
        RAISE EXCEPTION 'AAL2 authentication is required'
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

    IF v_preview_end < v_billing_start THEN
        RAISE EXCEPTION
            'Preview timestamp precedes the current billing segment'
            USING ERRCODE = '22023';
    END IF;

    v_contract_days :=
        public.business_contract_days(
            v_billing_start,
            v_preview_end
        );

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

    v_subtotal := v_daily_rate * v_contract_days;

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
$function$;

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

    IF coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
        RAISE EXCEPTION 'AAL2 authentication is required'
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

alter function public.get_billing_preview_state(uuid,timestamptz) owner to postgres;
alter function public.get_billing_workspace_state(timestamptz) owner to postgres;

revoke all on function public.get_billing_preview_state(uuid,timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.get_billing_workspace_state(timestamptz) from public, anon, authenticated, service_role;

grant execute on function public.get_billing_preview_state(uuid,timestamptz) to authenticated;
grant execute on function public.get_billing_workspace_state(timestamptz) to authenticated;
