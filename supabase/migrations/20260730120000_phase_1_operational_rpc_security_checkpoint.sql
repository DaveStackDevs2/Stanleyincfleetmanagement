CREATE OR REPLACE FUNCTION public.accept_case_extension_and_get_unified_payload_state(
  p_reservation_id uuid,
  p_new_expected_return_at timestamp with time zone,
  p_extension_amount numeric,
  p_extension_tax_amount numeric DEFAULT 0,
  p_reason_code text DEFAULT NULL::text,
  p_optional_note text DEFAULT NULL::text,
  p_entered_by_user_id uuid DEFAULT NULL::uuid,
  p_escalate_current_dependency boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid;
  v_action_result jsonb;
  v_unified_payload jsonb;
BEGIN
  SELECT au.id
  INTO v_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Billing action access denied'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
    RAISE EXCEPTION 'Billing action requires AAL2'
      USING ERRCODE = '42501';
  END IF;

  IF p_entered_by_user_id IS NOT NULL
     AND p_entered_by_user_id <> v_user_id THEN
    RAISE EXCEPTION 'Billing actor mismatch'
      USING ERRCODE = '42501';
  END IF;

  v_action_result :=
    public.accept_reservation_extension_state(
      p_reservation_id,
      p_new_expected_return_at,
      p_extension_amount,
      COALESCE(p_extension_tax_amount, 0),
      p_reason_code,
      p_optional_note,
      v_user_id,
      p_escalate_current_dependency
    );

  v_unified_payload :=
    public.get_unified_case_payload_state(p_reservation_id);

  RETURN jsonb_build_object(
    'status', 'case_extension_accepted_and_loaded',
    'reservation_id', p_reservation_id,
    'action_result', v_action_result,
    'unified_case_payload', v_unified_payload
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_case_and_get_unified_payload_state(
  p_reservation_id uuid,
  p_actual_in_at timestamp with time zone,
  p_end_mileage integer DEFAULT NULL::integer,
  p_close_billing boolean DEFAULT true,
  p_close_note text DEFAULT NULL::text,
  p_closed_by uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid;
  v_existing_end_mileage integer;
  v_effective_end_mileage integer;
  v_completion_result jsonb;
  v_unified_payload jsonb;
BEGIN
  SELECT au.id
  INTO v_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Billing action access denied'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
    RAISE EXCEPTION 'Billing action requires AAL2'
      USING ERRCODE = '42501';
  END IF;

  IF p_closed_by IS NOT NULL
     AND p_closed_by <> v_user_id THEN
    RAISE EXCEPTION 'Billing actor mismatch'
      USING ERRCODE = '42501';
  END IF;

  SELECT r.end_mileage
  INTO v_existing_end_mileage
  FROM public.reservations r
  WHERE r.id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
  END IF;

  v_effective_end_mileage :=
    COALESCE(p_end_mileage, v_existing_end_mileage);

  v_completion_result :=
    public.complete_case_return_and_close_state(
      p_reservation_id,
      p_actual_in_at,
      v_effective_end_mileage,
      p_close_billing,
      p_close_note,
      v_user_id
    );

  v_unified_payload :=
    public.get_unified_case_payload_state(p_reservation_id);

  RETURN jsonb_build_object(
    'status', 'case_completed_and_loaded',
    'reservation_id', p_reservation_id,
    'completion_result', v_completion_result,
    'unified_case_payload', v_unified_payload
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_case_and_get_unified_payload_state(
  p_reservation_id uuid,
  p_cancellation_reason text,
  p_closed_by uuid DEFAULT NULL::uuid,
  p_closed_at timestamp with time zone DEFAULT now(),
  p_note text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid;
  v_action_result jsonb;
  v_unified_payload jsonb;
BEGIN
  SELECT au.id
  INTO v_user_id
  FROM public.app_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.is_active = true;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Billing action access denied'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
    RAISE EXCEPTION 'Billing action requires AAL2'
      USING ERRCODE = '42501';
  END IF;

  IF p_closed_by IS NOT NULL
     AND p_closed_by <> v_user_id THEN
    RAISE EXCEPTION 'Billing actor mismatch'
      USING ERRCODE = '42501';
  END IF;

  v_action_result :=
    public.cancel_reservation_with_transportation_event_state(
      p_reservation_id,
      p_cancellation_reason,
      v_user_id,
      p_closed_at,
      p_note
    );

  v_unified_payload :=
    public.get_unified_case_payload_state(p_reservation_id);

  RETURN jsonb_build_object(
    'status', 'case_cancelled_and_loaded',
    'reservation_id', p_reservation_id,
    'action_result', v_action_result,
    'unified_case_payload', v_unified_payload
  );
END;
$function$;

ALTER FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid, timestamp with time zone, numeric, numeric, text, text, uuid, boolean) OWNER TO postgres;
ALTER FUNCTION public.complete_case_and_get_unified_payload_state(uuid, timestamp with time zone, integer, boolean, text, uuid) OWNER TO postgres;
ALTER FUNCTION public.cancel_case_and_get_unified_payload_state(uuid, text, uuid, timestamp with time zone, text) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid, timestamp with time zone, numeric, numeric, text, text, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_case_and_get_unified_payload_state(uuid, timestamp with time zone, integer, boolean, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cancel_case_and_get_unified_payload_state(uuid, text, uuid, timestamp with time zone, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.accept_case_extension_and_get_unified_payload_state(uuid, timestamp with time zone, numeric, numeric, text, text, uuid, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_case_and_get_unified_payload_state(uuid, timestamp with time zone, integer, boolean, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_case_and_get_unified_payload_state(uuid, text, uuid, timestamp with time zone, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.accept_reservation_extension_state(uuid, timestamp with time zone, numeric, numeric, text, text, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.accept_extension_commit_state(uuid, uuid, timestamp with time zone, numeric, numeric, text, text, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_expected_return_state(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.add_estimated_return_change_note_state(uuid, timestamp with time zone, timestamp with time zone, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.close_billing_line_at_paid_through_state(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_extension_billing_line_state(uuid, numeric, numeric, timestamp with time zone) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.escalate_dependency_to_critical_state(uuid, uuid) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.complete_case_return_and_close_state(uuid, timestamp with time zone, integer, boolean, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.return_reservation_vehicle_use_state(uuid, timestamp with time zone, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_reservation_actual_return_state(uuid, timestamp with time zone, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.close_current_reservation_billing_line_state(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.close_transportation_event_state(uuid, uuid, timestamp with time zone, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.return_vehicle_state(uuid, timestamp with time zone, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.close_billing_line_state(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.cancel_reservation_with_transportation_event_state(uuid, text, uuid, timestamp with time zone, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.accept_reservation_extension_state(uuid, timestamp with time zone, numeric, numeric, text, text, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.accept_extension_commit_state(uuid, uuid, timestamp with time zone, numeric, numeric, text, text, uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_expected_return_state(uuid, timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION public.add_estimated_return_change_note_state(uuid, timestamp with time zone, timestamp with time zone, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.close_billing_line_at_paid_through_state(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_extension_billing_line_state(uuid, numeric, numeric, timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION public.escalate_dependency_to_critical_state(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_case_return_and_close_state(uuid, timestamp with time zone, integer, boolean, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.return_reservation_vehicle_use_state(uuid, timestamp with time zone, integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_reservation_actual_return_state(uuid, timestamp with time zone, integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.close_current_reservation_billing_line_state(uuid, timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION public.close_transportation_event_state(uuid, uuid, timestamp with time zone, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.return_vehicle_state(uuid, timestamp with time zone, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.close_billing_line_state(uuid, timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_reservation_with_transportation_event_state(uuid, text, uuid, timestamp with time zone, text) TO service_role;
