-- Reconcile the already verified-live authoritative Extension boundary and wrapper.
-- This migration is data-free and reuses the existing preview and Extension engines.
DO $migration$
DECLARE
  v_preview regprocedure := to_regprocedure('public.get_billing_preview_state(uuid,timestamptz)');
  v_definition text;
  v_boundary_at integer; v_current_start integer; v_current_end integer;
  v_closed_start integer; v_closed_key integer; v_active_key integer;
  v_expression_start integer; v_expression_end integer;
  v_current_replacement text := E'v_contract_days := CASE\n        WHEN v_current_line.line_type = ''rental_extension''\n         AND v_current_line.extended_from_billing_line_id IS NOT NULL\n        THEN greatest(0, public.business_contract_days(v_billing_start, v_preview_end) - 1)\n        ELSE public.business_contract_days(v_billing_start, v_preview_end)\n    END;';
  v_closed_replacement text := E'CASE\n                            WHEN parent.start_time IS NULL THEN NULL\n                            WHEN parent.line_type = ''rental_extension''\n                             AND parent.extended_from_billing_line_id IS NOT NULL\n                            THEN greatest(0, public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, v_event.closed_at, p_effective_at)) - 1)\n                            ELSE public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, v_event.closed_at, p_effective_at))\n                        END';
  v_active_replacement text := E'CASE\n                        WHEN parent.start_time IS NULL THEN NULL\n                        WHEN parent.line_type = ''rental_extension''\n                         AND parent.extended_from_billing_line_id IS NOT NULL\n                        THEN greatest(0, public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, p_effective_at)) - 1)\n                        ELSE public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, p_effective_at))\n                    END';
BEGIN
  IF v_preview IS NULL THEN RAISE EXCEPTION 'Expected Billing preview signature is missing'; END IF;
  v_definition := replace(pg_get_functiondef('public.get_billing_preview_state(uuid,timestamptz)'::regprocedure), chr(13), '');

  IF regexp_count(v_definition, 'v_current_line\.line_type = ''rental_extension''') = 1
     AND regexp_count(v_definition, 'parent\.line_type = ''rental_extension''') = 2 THEN
    RETURN;
  ELSIF regexp_count(v_definition, 'rental_extension') <> 0 THEN
    RAISE EXCEPTION 'Billing preview Extension reconciliation is only partially applied';
  END IF;

  -- Use verified structural ranges, not formatting-sensitive source replacement.
  v_boundary_at := strpos(v_definition, 'IF v_preview_end < v_billing_start THEN');
  v_current_start := v_boundary_at + strpos(substr(v_definition, v_boundary_at), 'v_contract_days :=') - 1;
  v_current_end := v_current_start + strpos(substr(v_definition, v_current_start), ';') - 1;
  v_closed_start := strpos(v_definition, 'IF v_event.status IN (''closed'',''completed'',''cancelled'') THEN');
  v_closed_key := v_closed_start + strpos(substr(v_definition, v_closed_start), '''contract_days''') - 1;
  v_active_key := v_current_end + strpos(substr(v_definition, v_current_end + 1), '''contract_days''');
  IF v_boundary_at = 0 OR v_current_start < v_boundary_at OR v_current_end < v_current_start
     OR v_closed_start = 0 OR v_closed_key < v_closed_start OR v_closed_key > v_boundary_at
     OR v_active_key <= v_current_end THEN
    RAISE EXCEPTION 'Billing preview structural anchors have drifted';
  END IF;

  -- Splice back-to-front so earlier offsets remain stable.
  v_expression_start := v_active_key + strpos(substr(v_definition, v_active_key), ',');
  v_expression_end := v_expression_start + strpos(substr(v_definition, v_expression_start + 1), '''is_open''') - 1;
  IF v_expression_end <= v_expression_start THEN RAISE EXCEPTION 'Active segment contract-days range has drifted'; END IF;
  v_definition := substr(v_definition, 1, v_expression_start) || v_active_replacement || ',' || substr(v_definition, v_expression_end + 1);

  v_definition := substr(v_definition, 1, v_current_start - 1) || v_current_replacement || substr(v_definition, v_current_end + 1);

  v_expression_start := v_closed_key + strpos(substr(v_definition, v_closed_key), ',');
  v_expression_end := v_expression_start + strpos(substr(v_definition, v_expression_start + 1), '''is_open''') - 1;
  IF v_expression_end <= v_expression_start THEN RAISE EXCEPTION 'Closed segment contract-days range has drifted'; END IF;
  v_definition := substr(v_definition, 1, v_expression_start) || v_closed_replacement || ',' || substr(v_definition, v_expression_end + 1);

  IF regexp_count(v_definition, 'v_current_line\.line_type = ''rental_extension''') <> 1 THEN
    RAISE EXCEPTION 'Billing preview current-segment definition has drifted';
  END IF;
  IF regexp_count(v_definition, 'parent\.line_type = ''rental_extension''') <> 2 THEN
    RAISE EXCEPTION 'Billing preview segment-history definitions have drifted';
  END IF;
  EXECUTE v_definition;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.accept_case_extension_and_get_unified_payload_state(
  p_reservation_id uuid, p_new_expected_return_at timestamptz, p_extension_amount numeric,
  p_extension_tax_amount numeric DEFAULT NULL, p_reason_code text DEFAULT NULL,
  p_optional_note text DEFAULT NULL, p_entered_by_user_id uuid DEFAULT NULL,
  p_escalate_current_dependency boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
  v_user_id uuid; v_candidate record; v_current_line public.billing_lines%ROWTYPE;
  v_current_expected_return_at timestamptz;
  v_preview jsonb; v_authoritative_extension_amount numeric; v_action_result jsonb; v_unified_payload jsonb;
BEGIN
  SELECT au.id INTO v_user_id FROM public.app_users au
  WHERE au.auth_user_id=auth.uid() AND au.is_active=true;
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Billing action access denied' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN RAISE EXCEPTION 'Billing action requires AAL2' USING ERRCODE='42501'; END IF;
  IF p_entered_by_user_id IS NOT NULL AND p_entered_by_user_id<>v_user_id THEN RAISE EXCEPTION 'Billing actor mismatch' USING ERRCODE='42501'; END IF;
  IF p_reservation_id IS NULL OR p_new_expected_return_at IS NULL THEN RAISE EXCEPTION 'Reservation and new expected return are required' USING ERRCODE='22023'; END IF;
  IF p_reason_code IS NULL OR btrim(p_reason_code)='' THEN RAISE EXCEPTION 'Extension reason is required' USING ERRCODE='22023'; END IF;

  SELECT * INTO v_candidate FROM public.v_reservation_extension_candidate_state
  WHERE reservation_id=p_reservation_id AND parent_billing_line_id IS NOT NULL
  ORDER BY start_time DESC NULLS LAST,parent_billing_line_id DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'No extension-eligible billing line exists' USING ERRCODE='P0002'; END IF;

  SELECT line.* INTO v_current_line FROM public.billing_lines line
  WHERE line.id=v_candidate.parent_billing_line_id
    AND line.reservation_id=p_reservation_id
    AND line.transportation_event_id=v_candidate.transportation_event_id
    AND line.parent_billing_line_id IS NULL
    AND line.line_type IS DISTINCT FROM 'tax'
    AND line.is_open=true FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Current extension billing line changed' USING ERRCODE='40001'; END IF;
  IF v_current_line.paid_through_at IS NULL THEN RAISE EXCEPTION 'Mark billed through before extending' USING ERRCODE='22023'; END IF;
  IF v_current_line.line_type='rental_extension' AND v_current_line.extended_from_billing_line_id IS NOT NULL
     AND v_current_line.paid_through_at<=v_current_line.start_time THEN
    RAISE EXCEPTION 'Current Extension must advance billed-through before another Extension' USING ERRCODE='22023';
  END IF;
  v_current_expected_return_at := coalesce(v_candidate.current_expected_return_at, v_candidate.expected_return_datetime);
  IF v_current_expected_return_at IS NULL OR p_new_expected_return_at<=v_current_expected_return_at
     OR p_new_expected_return_at<=v_current_line.paid_through_at THEN
    RAISE EXCEPTION 'New expected return must be later than the current return and billed-through boundary' USING ERRCODE='22023';
  END IF;

  v_preview:=public.get_billing_preview_state(v_candidate.transportation_event_id,p_new_expected_return_at);
  IF v_preview->>'status' IS DISTINCT FROM 'billing_preview_ready' THEN RAISE EXCEPTION 'Authoritative Billing preview is not ready'; END IF;
  IF (v_preview->>'current_billing_line_id')::uuid IS DISTINCT FROM v_current_line.id THEN RAISE EXCEPTION 'Billing preview current line changed' USING ERRCODE='40001'; END IF;
  IF v_preview->>'subtotal' IS NULL OR v_current_line.amount IS NULL THEN RAISE EXCEPTION 'Authoritative extension amounts are unavailable'; END IF;
  v_authoritative_extension_amount:=(v_preview->>'subtotal')::numeric-v_current_line.amount;
  IF v_authoritative_extension_amount<0 THEN RAISE EXCEPTION 'Authoritative extension amount cannot be negative' USING ERRCODE='22023'; END IF;

  v_action_result:=public.accept_reservation_extension_state(p_reservation_id,p_new_expected_return_at,
    v_authoritative_extension_amount,NULL,p_reason_code,p_optional_note,v_user_id,p_escalate_current_dependency);
  v_unified_payload:=public.get_unified_case_payload_state(p_reservation_id);
  RETURN jsonb_build_object('status','case_extension_accepted_and_loaded','reservation_id',p_reservation_id,
    'transportation_event_id',v_candidate.transportation_event_id,
    'previous_expected_return_at',v_current_expected_return_at,'new_expected_return_at',p_new_expected_return_at,
    'previous_billing_line_id',v_current_line.id,'billed_through_at',v_current_line.paid_through_at,
    'authoritative_extension_amount',v_authoritative_extension_amount::text,
    'submitted_amounts_ignored',true,'proposed_billing_preview',v_preview,'action_result',v_action_result,'unified_case_payload',v_unified_payload);
END;
$function$;

ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SET search_path TO '';
ALTER FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) OWNER TO postgres;
ALTER FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) SECURITY DEFINER;
ALTER FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) SET search_path TO '';
REVOKE ALL ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) TO authenticated;
