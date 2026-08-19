-- Reconcile the verified-live closed Billing review contracts without data changes.
-- The preview edit is drift-safe: an already reconciled live definition is left intact;
-- the known active definition receives only an early stored-history branch.
DO $migration$
DECLARE
  v_preview regprocedure := to_regprocedure('public.get_billing_preview_state(uuid,timestamptz)');
  v_definition text;
  v_insertion text := $closed$
    -- VERIFIED CLOSED BILLING SNAPSHOT BRANCH. Keep before open/current continuity assumptions.
    IF lower(btrim(v_event.status)) = 'closed' THEN
        IF v_event.closed_at IS NULL OR p_effective_at < v_event.closed_at THEN
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
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at,'missing_dependency','stored_billing_history');
        END IF;

        IF EXISTS (SELECT 1 FROM public.billing_lines line WHERE line.transportation_event_id=p_transportation_event_id AND line.is_open)
           OR EXISTS (
                SELECT 1 FROM public.billing_lines parent
                LEFT JOIN LATERAL (SELECT count(*) AS child_count, coalesce(sum(tax.amount),0) AS child_tax FROM public.billing_lines tax WHERE tax.parent_billing_line_id=parent.id AND tax.line_type='tax') stored_tax ON true
                WHERE parent.transportation_event_id=p_transportation_event_id AND parent.parent_billing_line_id IS NULL
                  AND (stored_tax.child_count > 1 OR stored_tax.child_tax <> coalesce(parent.tax_amount,0))
           ) THEN
            RETURN jsonb_build_object('status','billing_preview_unavailable','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at);
        END IF;

        SELECT vehicle_event.* INTO v_vehicle_event FROM public.vehicle_events vehicle_event
        WHERE vehicle_event.id=v_current_line.vehicle_event_id
        LIMIT 1;
        IF NOT FOUND THEN
            SELECT vehicle_event.* INTO v_vehicle_event FROM public.vehicle_events vehicle_event
            WHERE vehicle_event.transportation_event_id=p_transportation_event_id
            ORDER BY coalesce(vehicle_event.actual_in_at,vehicle_event.actual_out_at) DESC NULLS LAST,vehicle_event.id DESC LIMIT 1;
        END IF;
        IF v_vehicle_event.id IS NULL OR v_vehicle_event.actual_out_at IS NULL THEN
            RETURN jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'effective_at',p_effective_at,'missing_dependency','historical_vehicle_assignment');
        END IF;

        SELECT contract_period.* INTO v_contract_period FROM public.contract_periods contract_period
        WHERE contract_period.id=v_current_line.contract_period_id LIMIT 1;
        IF NOT FOUND THEN
            SELECT contract_period.* INTO v_contract_period FROM public.contract_periods contract_period
            WHERE contract_period.vehicle_event_id=v_vehicle_event.id
            ORDER BY contract_period.renewal_sequence DESC,contract_period.contract_out_at DESC,contract_period.id DESC LIMIT 1;
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
            'paid_through_at',parent.paid_through_at,'contract_days',CASE WHEN parent.start_time IS NULL THEN NULL ELSE public.business_contract_days(parent.start_time,coalesce(parent.end_time,parent.paid_through_at,v_event.closed_at,p_effective_at)) END,
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
          'billed_through_at',coalesce(v_current_line.paid_through_at,v_reservation.billed_through_datetime),'current_billing_line_id',v_current_line.id,
          'line_type',v_current_line.line_type,'pay_type_rule_id',v_current_line.pay_type_rule_id,'pay_type',v_pay_type,
          'vehicle_class',v_reservation.requested_model,'billing_start',v_billing_start,'preview_end',v_preview_end,'effective_at',p_effective_at,
          'contract_days',v_contract_days,'daily_rate',v_daily_rate::text,'rate_source','stored_closed_billing_snapshot',
          'subtotal',v_subtotal::text,'is_taxable',v_is_taxable,'tax_rate',v_tax_rate::text,'tax_amount',v_tax_amount::text,
          'tax_rate_source',v_current_line.tax_rate_source_snapshot,'tax_explanation','Closed billing uses stored historical line snapshots without recalculation.',
          'total',v_total::text,'historical_subtotal',v_accumulated_subtotal::text,'historical_tax',v_accumulated_tax::text,
          'accumulated_subtotal',v_accumulated_subtotal::text,'accumulated_tax',v_accumulated_tax::text,'accumulated_total',v_accumulated_total::text,
          'segments',v_segments,'extended_warranty',v_extended_warranty);
    END IF;

$closed$;
  v_anchor text := E'    IF (\n        SELECT count(*)\n        FROM public.vehicle_events vehicle_event';
BEGIN
  IF v_preview IS NULL THEN RAISE EXCEPTION 'Expected Billing preview signature is missing'; END IF;
  v_definition := pg_get_functiondef(v_preview);
  IF position('stored_closed_billing_snapshot' IN v_definition) = 0 THEN
    IF position(v_anchor IN v_definition) = 0 OR position('billing_preview_ready' IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Billing preview definition has drifted from the verified active contract';
    END IF;
    v_definition := replace(v_definition,v_anchor,v_insertion || v_anchor);
    EXECUTE v_definition;
  ELSIF position('Closed billing uses stored historical line snapshots without recalculation.' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Closed Billing preview definition is only partially reconciled';
  END IF;
END;
$migration$;

DROP FUNCTION IF EXISTS public.get_closed_billing_workspace_state(integer);

CREATE OR REPLACE FUNCTION public.get_closed_billing_workspace_state(
  p_case_scope text DEFAULT 'all', p_closed_from timestamptz DEFAULT NULL,
  p_closed_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 50
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
  v_actor_user_id uuid; v_lifecycle jsonb; v_case jsonb; v_preview jsonb; v_items jsonb := '[]'::jsonb;
  v_scope text := lower(btrim(coalesce(p_case_scope,'all'))); v_limit integer := p_limit;
  v_case_count integer := 0; v_ready_count integer := 0; v_attention_count integer := 0;
  v_accumulated_subtotal numeric := 0; v_accumulated_tax numeric := 0; v_accumulated_total numeric := 0;
BEGIN
  SELECT app_user.id INTO v_actor_user_id FROM public.app_users app_user WHERE app_user.auth_user_id=auth.uid() AND app_user.is_active=true;
  IF v_actor_user_id IS NULL THEN RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN RAISE EXCEPTION 'AAL2 authentication is required' USING ERRCODE='42501'; END IF;
  IF v_scope NOT IN ('all','rental','loaner') THEN RAISE EXCEPTION 'Case scope must be all, rental, or loaner' USING ERRCODE='22023'; END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN RAISE EXCEPTION 'Limit must be between 1 and 200' USING ERRCODE='22023'; END IF;
  IF p_closed_from IS NOT NULL AND p_closed_before IS NOT NULL AND p_closed_from >= p_closed_before THEN RAISE EXCEPTION 'Closed date range is invalid' USING ERRCODE='22023'; END IF;
  v_lifecycle := public.get_reservation_lifecycle_list_state();
  IF v_lifecycle->>'status' <> 'reservation_lifecycle_list_ready' THEN
    RAISE EXCEPTION 'Reservation lifecycle list is unavailable';
  END IF;
  FOR v_case IN SELECT value FROM jsonb_array_elements(coalesce(v_lifecycle->'items','[]'::jsonb)) value
    WHERE lower(btrim(value->>'transportation_event_status'))='closed'
      AND value->>'closed_at' IS NOT NULL
      AND (v_scope='all' OR lower(btrim(value->>'reservation_type'))=v_scope)
      AND (p_closed_from IS NULL OR (value->>'closed_at')::timestamptz >= p_closed_from)
      AND (p_closed_before IS NULL OR (value->>'closed_at')::timestamptz < p_closed_before)
      AND EXISTS (SELECT 1 FROM public.billing_lines line WHERE line.transportation_event_id=(value->>'transportation_event_id')::uuid AND line.parent_billing_line_id IS NULL)
    ORDER BY (value->>'closed_at')::timestamptz DESC, value->>'transportation_event_id' LIMIT v_limit
  LOOP
    BEGIN v_preview := public.get_billing_preview_state((v_case->>'transportation_event_id')::uuid,(v_case->>'closed_at')::timestamptz);
    EXCEPTION WHEN OTHERS THEN v_preview:=jsonb_build_object('status','billing_preview_unavailable','transportation_event_id',v_case->>'transportation_event_id','effective_at',v_case->>'closed_at'); END;
    v_case_count:=v_case_count+1;
    IF v_preview->>'status'='billing_preview_ready' THEN v_ready_count:=v_ready_count+1; v_accumulated_subtotal:=v_accumulated_subtotal+(v_preview->>'accumulated_subtotal')::numeric; v_accumulated_tax:=v_accumulated_tax+(v_preview->>'accumulated_tax')::numeric; v_accumulated_total:=v_accumulated_total+(v_preview->>'accumulated_total')::numeric; ELSE v_attention_count:=v_attention_count+1; END IF;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('transportation_event_id',v_case->>'transportation_event_id','source_type',v_case->>'source_type','source_id',v_case->>'source_id','closed_at',v_case->>'closed_at','expected_return_at',v_case->>'expected_return_at','reservation',jsonb_build_object('reservation_id',v_case->>'reservation_id','status',v_case->>'reservation_status','reservation_type',v_case->>'reservation_type','ro_number',v_case->>'ro_number','requested_model',v_case->>'requested_model','pay_type',v_case->>'pay_type','start_date',v_case->>'start_date','expected_return_datetime',v_case->>'expected_return_datetime','actual_return_datetime',v_case->>'actual_return_datetime','billed_through_datetime',v_case->>'billed_through_datetime'),'preview',v_preview));
  END LOOP;
  RETURN jsonb_build_object('status','closed_billing_workspace_ready','date_field','transportation_event.closed_at','date_label','Case closed','case_scope',v_scope,'closed_from',p_closed_from,'closed_before',p_closed_before,'limit',v_limit,'case_count',v_case_count,'ready_count',v_ready_count,'attention_count',v_attention_count,'accumulated_subtotal',v_accumulated_subtotal::text,'accumulated_tax',v_accumulated_tax::text,'accumulated_total',v_accumulated_total::text,'items',v_items);
END;
$function$;

ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SET search_path TO '';
ALTER FUNCTION public.get_closed_billing_workspace_state(text,timestamptz,timestamptz,integer) OWNER TO postgres;
ALTER FUNCTION public.get_closed_billing_workspace_state(text,timestamptz,timestamptz,integer) SECURITY DEFINER;
ALTER FUNCTION public.get_closed_billing_workspace_state(text,timestamptz,timestamptz,integer) SET search_path TO '';
REVOKE ALL ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.get_closed_billing_workspace_state(text,timestamptz,timestamptz,integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_closed_billing_workspace_state(text,timestamptz,timestamptz,integer) TO authenticated;
