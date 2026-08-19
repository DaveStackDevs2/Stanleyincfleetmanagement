-- Reconcile the verified-live Return/Complete engine that persists the authoritative
-- final preview amounts before continuity and Billing are closed.
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

        v_final_subtotal := (v_final_preview->>'subtotal')::numeric;
        v_final_tax := (v_final_preview->>'tax_amount')::numeric;
        UPDATE public.billing_lines
        SET amount = v_final_subtotal,
            tax_amount = v_final_tax,
            updated_at = now()
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
        'return_result', v_return_result,
        'billing_close_result', v_billing_close_result,
        'transportation_event_close_result', v_transportation_close_result
    );
END;
$function$;

ALTER FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) OWNER TO postgres;
ALTER FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) SECURITY INVOKER;
ALTER FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) RESET ALL;
REVOKE ALL ON FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) TO service_role;
