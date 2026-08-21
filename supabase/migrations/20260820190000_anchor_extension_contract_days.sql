-- Preserve the Reservation's scheduled Billing boundary across Extension checkpoints.
-- This migration is data-free and changes only the authoritative Billing preview.
DO $migration$
DECLARE
  v_preview regprocedure := to_regprocedure('public.get_billing_preview_state(uuid,timestamptz)');
  v_definition text;
  v_current_at integer; v_closed_at integer; v_active_at integer;
  v_current_old text := E'greatest(0, public.business_contract_days(v_billing_start, v_preview_end) - 1)';
  v_current_new text := E'greatest(0, public.business_contract_days(v_reservation.start_date, v_preview_end) - public.business_contract_days(v_reservation.start_date, v_billing_start))';
  v_closed_old text := E'greatest(0, public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, v_event.closed_at, p_effective_at)) - 1)';
  v_closed_new text := E'greatest(0, public.business_contract_days(v_reservation.start_date, coalesce(parent.end_time, parent.paid_through_at, v_event.closed_at, p_effective_at)) - public.business_contract_days(v_reservation.start_date, parent.start_time))';
  v_active_old text := E'greatest(0, public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, p_effective_at)) - 1)';
  v_active_new text := E'greatest(0, public.business_contract_days(v_reservation.start_date, coalesce(parent.end_time, parent.paid_through_at, p_effective_at)) - public.business_contract_days(v_reservation.start_date, parent.start_time))';
BEGIN
  IF v_preview IS NULL THEN
    RAISE EXCEPTION 'Expected Billing preview signature is missing';
  END IF;
  v_definition := replace(pg_get_functiondef(v_preview), chr(13), '');

  -- Accept only the complete target state or the exact three verified source branches.
  IF (length(v_definition) - length(replace(v_definition, v_current_new, ''))) / length(v_current_new) = 1
     AND (length(v_definition) - length(replace(v_definition, v_closed_new, ''))) / length(v_closed_new) = 1
     AND (length(v_definition) - length(replace(v_definition, v_active_new, ''))) / length(v_active_new) = 1 THEN
    IF regexp_count(v_definition, 'v_current_line\.line_type = ''rental_extension''') <> 1
       OR regexp_count(v_definition, 'parent\.line_type = ''rental_extension''') <> 2
       OR strpos(v_definition, v_current_old) <> 0
       OR strpos(v_definition, v_closed_old) <> 0
       OR strpos(v_definition, v_active_old) <> 0 THEN
      RAISE EXCEPTION 'Anchored Billing preview target is partial or drifted';
    END IF;
    RETURN;
  END IF;

  IF (length(v_definition) - length(replace(v_definition, v_current_old, ''))) / length(v_current_old) <> 1
     OR (length(v_definition) - length(replace(v_definition, v_closed_old, ''))) / length(v_closed_old) <> 1
     OR (length(v_definition) - length(replace(v_definition, v_active_old, ''))) / length(v_active_old) <> 1
     OR regexp_count(v_definition, 'v_current_line\.line_type = ''rental_extension''') <> 1
     OR regexp_count(v_definition, 'parent\.line_type = ''rental_extension''') <> 2
     OR strpos(v_definition, v_current_new) <> 0
     OR strpos(v_definition, v_closed_new) <> 0
     OR strpos(v_definition, v_active_new) <> 0 THEN
    RAISE EXCEPTION 'Billing preview Extension anchors are partial or drifted';
  END IF;

  v_current_at := strpos(v_definition, v_current_old);
  v_closed_at := strpos(v_definition, v_closed_old);
  v_active_at := strpos(v_definition, v_active_old);
  IF NOT (v_closed_at < v_current_at AND v_current_at < v_active_at) THEN
    RAISE EXCEPTION 'Billing preview Extension branch order has drifted';
  END IF;

  -- Splice the three validated expressions back-to-front; do not globally replace SQL.
  v_definition := substr(v_definition, 1, v_active_at - 1) || v_active_new || substr(v_definition, v_active_at + length(v_active_old));
  v_definition := substr(v_definition, 1, v_current_at - 1) || v_current_new || substr(v_definition, v_current_at + length(v_current_old));
  v_definition := substr(v_definition, 1, v_closed_at - 1) || v_closed_new || substr(v_definition, v_closed_at + length(v_closed_old));

  IF (length(v_definition) - length(replace(v_definition, v_current_new, ''))) / length(v_current_new) <> 1
     OR (length(v_definition) - length(replace(v_definition, v_closed_new, ''))) / length(v_closed_new) <> 1
     OR (length(v_definition) - length(replace(v_definition, v_active_new, ''))) / length(v_active_new) <> 1
     OR strpos(v_definition, v_current_old) <> 0
     OR strpos(v_definition, v_closed_old) <> 0
     OR strpos(v_definition, v_active_old) <> 0
     OR regexp_count(v_definition, 'v_current_line\.line_type = ''rental_extension''') <> 1
     OR regexp_count(v_definition, 'parent\.line_type = ''rental_extension''') <> 2 THEN
    RAISE EXCEPTION 'Anchored Billing preview validation failed';
  END IF;
  EXECUTE v_definition;
END;
$migration$;

ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SET search_path TO '';
REVOKE ALL ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) TO authenticated;
