-- Record the verified live read-only Billing RPC follow-up without touching data.
-- Each definition is changed only when its exact prior text is present. A partially
-- changed or otherwise drifted definition aborts rather than guessing.
DO $migration$
DECLARE
    v_preview regprocedure :=
        to_regprocedure('public.get_billing_preview_state(uuid,timestamptz)');
    v_workspace regprocedure :=
        to_regprocedure('public.get_billing_workspace_state(timestamptz)');
    v_definition text;
    v_changed boolean := false;
    v_aal2_block text := E'    IF coalesce(auth.jwt() ->> ''aal'', '''') <> ''aal2'' THEN\n        RAISE EXCEPTION ''AAL2 authentication is required''\n            USING ERRCODE = ''42501'';\n    END IF;\n\n';
    v_ro_select_old text := E'            reservation.id AS reservation_id,\n            reservation.status AS reservation_status,';
    v_ro_select_new text := E'            reservation.id AS reservation_id,\n            reservation.ro_number,\n            reservation.status AS reservation_status,';
    v_ro_payload_old text := E'                ''reservation_id'', v_case.reservation_id,\n                ''status'', v_case.reservation_status,';
    v_ro_payload_new text := E'                ''reservation_id'', v_case.reservation_id,\n                ''ro_number'', v_case.ro_number,\n                ''status'', v_case.reservation_status,';
BEGIN
    IF v_preview IS NULL OR v_workspace IS NULL THEN
        RAISE EXCEPTION
            'Expected operational Billing RPC signatures are missing';
    END IF;

    v_definition := pg_get_functiondef(v_preview);
    IF position('app_user.is_active = true' IN v_definition) = 0 THEN
        RAISE EXCEPTION
            'Billing preview active-user validation has drifted';
    END IF;
    IF position(v_aal2_block IN v_definition) > 0 THEN
        v_definition := replace(v_definition, v_aal2_block, '');
        EXECUTE v_definition;
    ELSIF position('AAL2 authentication is required' IN v_definition) > 0
       OR position('auth.jwt() ->> ''aal''' IN v_definition) > 0 THEN
        RAISE EXCEPTION
            'Billing preview AAL2 insertion point has drifted';
    END IF;

    v_definition := pg_get_functiondef(v_workspace);
    v_changed := false;
    IF position('app_user.is_active = true' IN v_definition) = 0 THEN
        RAISE EXCEPTION
            'Billing workspace active-user validation has drifted';
    END IF;
    IF position(v_aal2_block IN v_definition) > 0 THEN
        v_definition := replace(v_definition, v_aal2_block, '');
        v_changed := true;
    ELSIF position('AAL2 authentication is required' IN v_definition) > 0
       OR position('auth.jwt() ->> ''aal''' IN v_definition) > 0 THEN
        RAISE EXCEPTION
            'Billing workspace AAL2 insertion point has drifted';
    END IF;

    IF position(v_ro_select_new IN v_definition) = 0 THEN
        IF position(v_ro_select_old IN v_definition) = 0 THEN
            RAISE EXCEPTION
                'Billing workspace reservation RO select insertion point has drifted';
        END IF;
        v_definition := replace(
            v_definition,
            v_ro_select_old,
            v_ro_select_new
        );
        v_changed := true;
    END IF;

    IF position(v_ro_payload_new IN v_definition) = 0 THEN
        IF position(v_ro_payload_old IN v_definition) = 0 THEN
            RAISE EXCEPTION
                'Billing workspace reservation RO payload insertion point has drifted';
        END IF;
        v_definition := replace(
            v_definition,
            v_ro_payload_old,
            v_ro_payload_new
        );
        v_changed := true;
    END IF;

    IF v_changed THEN
        EXECUTE v_definition;
    END IF;
END;
$migration$;

ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz)
    OWNER TO postgres;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz)
    SECURITY DEFINER;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz)
    SET search_path TO '';
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz)
    VOLATILE;

ALTER FUNCTION public.get_billing_workspace_state(timestamptz)
    OWNER TO postgres;
ALTER FUNCTION public.get_billing_workspace_state(timestamptz)
    SECURITY DEFINER;
ALTER FUNCTION public.get_billing_workspace_state(timestamptz)
    SET search_path TO '';
ALTER FUNCTION public.get_billing_workspace_state(timestamptz)
    VOLATILE;

REVOKE ALL ON FUNCTION public.get_billing_preview_state(uuid,timestamptz)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_billing_workspace_state(timestamptz)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_billing_preview_state(uuid,timestamptz)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_billing_workspace_state(timestamptz)
    TO authenticated;
