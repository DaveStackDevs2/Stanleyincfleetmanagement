-- Preserve the Reservation's scheduled Billing boundary across Extension checkpoints.
-- This migration is data-free and changes only the authoritative Billing preview.
DO $migration$
DECLARE
  v_preview regprocedure := to_regprocedure('public.get_billing_preview_state(uuid,timestamptz)');
  v_definition text;
  v_current_condition integer; v_closed_condition integer; v_active_condition integer;
  v_current_then integer; v_current_else integer;
  v_closed_then integer; v_closed_else integer;
  v_active_then integer; v_active_else integer;
  v_current_expression text; v_closed_expression text; v_active_expression text;
  v_current_old text := 'greatest(0, public.business_contract_days(v_billing_start, v_preview_end) - 1)';
  v_current_new text := 'greatest(0, public.business_contract_days(v_reservation.start_date, v_preview_end) - public.business_contract_days(v_reservation.start_date, v_billing_start))';
  v_closed_old text := 'greatest(0, public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, v_event.closed_at, p_effective_at)) - 1)';
  v_closed_new text := 'greatest(0, public.business_contract_days(v_reservation.start_date, coalesce(parent.end_time, parent.paid_through_at, v_event.closed_at, p_effective_at)) - public.business_contract_days(v_reservation.start_date, parent.start_time))';
  v_active_old text := 'greatest(0, public.business_contract_days(parent.start_time, coalesce(parent.end_time, parent.paid_through_at, p_effective_at)) - 1)';
  v_active_new text := 'greatest(0, public.business_contract_days(v_reservation.start_date, coalesce(parent.end_time, parent.paid_through_at, p_effective_at)) - public.business_contract_days(v_reservation.start_date, parent.start_time))';
  v_current_old_compact text; v_current_new_compact text;
  v_closed_old_compact text; v_closed_new_compact text;
  v_active_old_compact text; v_active_new_compact text;
BEGIN
  IF v_preview IS NULL THEN
    RAISE EXCEPTION 'Expected Billing preview signature is missing';
  END IF;
  v_definition := replace(pg_get_functiondef(v_preview), chr(13), '');

  -- Locate the three verified Extension CASE arms. Expression whitespace is deliberately
  -- excluded from the anchors because pg_get_functiondef formats these arms multiline.
  IF regexp_count(v_definition, 'v_current_line\.line_type = ''rental_extension''') <> 1
     OR regexp_count(v_definition, 'parent\.line_type = ''rental_extension''') <> 2 THEN
    RAISE EXCEPTION 'Billing preview Extension branch shape has drifted';
  END IF;
  v_current_condition := strpos(v_definition, 'v_current_line.line_type = ''rental_extension''');
  v_closed_condition := strpos(v_definition, 'parent.line_type = ''rental_extension''');
  v_active_condition := v_closed_condition + strpos(substr(v_definition, v_closed_condition + 1), 'parent.line_type = ''rental_extension''');
  IF v_current_condition = 0 OR v_closed_condition = 0 OR v_active_condition <= v_closed_condition
     OR NOT (v_closed_condition < v_current_condition AND v_current_condition < v_active_condition) THEN
    RAISE EXCEPTION 'Billing preview Extension branch order has drifted';
  END IF;

  v_current_then := v_current_condition + strpos(substr(v_definition, v_current_condition), 'THEN') - 1;
  v_current_else := v_current_then + strpos(substr(v_definition, v_current_then), 'ELSE') - 1;
  v_closed_then := v_closed_condition + strpos(substr(v_definition, v_closed_condition), 'THEN') - 1;
  v_closed_else := v_closed_then + strpos(substr(v_definition, v_closed_then), 'ELSE') - 1;
  v_active_then := v_active_condition + strpos(substr(v_definition, v_active_condition), 'THEN') - 1;
  v_active_else := v_active_then + strpos(substr(v_definition, v_active_then), 'ELSE') - 1;
  IF v_current_then < v_current_condition OR v_current_else <= v_current_then
     OR v_closed_then < v_closed_condition OR v_closed_else <= v_closed_then
     OR v_active_then < v_active_condition OR v_active_else <= v_active_then THEN
    RAISE EXCEPTION 'Billing preview Extension CASE structure has drifted';
  END IF;

  -- Remove all whitespace for validation because pg_get_functiondef may also insert
  -- spaces immediately inside function-call parentheses. Retain structural offsets
  -- into the unmodified definition for each splice.
  v_current_expression := regexp_replace(substr(v_definition, v_current_then + 4, v_current_else - v_current_then - 4), '[[:space:]]', '', 'g');
  v_closed_expression := regexp_replace(substr(v_definition, v_closed_then + 4, v_closed_else - v_closed_then - 4), '[[:space:]]', '', 'g');
  v_active_expression := regexp_replace(substr(v_definition, v_active_then + 4, v_active_else - v_active_then - 4), '[[:space:]]', '', 'g');

  v_current_old_compact := regexp_replace(v_current_old, '[[:space:]]', '', 'g');
  v_current_new_compact := regexp_replace(v_current_new, '[[:space:]]', '', 'g');
  v_closed_old_compact := regexp_replace(v_closed_old, '[[:space:]]', '', 'g');
  v_closed_new_compact := regexp_replace(v_closed_new, '[[:space:]]', '', 'g');
  v_active_old_compact := regexp_replace(v_active_old, '[[:space:]]', '', 'g');
  v_active_new_compact := regexp_replace(v_active_new, '[[:space:]]', '', 'g');

  -- Recognize only the complete target or complete predecessor; mixed/drifted states fail closed.
  IF v_current_expression = v_current_new_compact
     AND v_closed_expression = v_closed_new_compact
     AND v_active_expression = v_active_new_compact THEN
    RETURN;
  END IF;
  IF v_current_expression <> v_current_old_compact
     OR v_closed_expression <> v_closed_old_compact
     OR v_active_expression <> v_active_old_compact THEN
    RAISE EXCEPTION 'Billing preview Extension anchors are partial or drifted';
  END IF;

  -- Splice validated CASE-arm ranges back-to-front; never globally replace an expression.
  v_definition := substr(v_definition, 1, v_active_then + 3)
    || E'\n                        ' || v_active_new || E'\n                    '
    || substr(v_definition, v_active_else);
  v_definition := substr(v_definition, 1, v_current_then + 3)
    || E'\n        ' || v_current_new || E'\n        '
    || substr(v_definition, v_current_else);
  v_definition := substr(v_definition, 1, v_closed_then + 3)
    || E'\n                            ' || v_closed_new || E'\n                        '
    || substr(v_definition, v_closed_else);

  IF regexp_count(v_definition, 'v_current_line\.line_type = ''rental_extension''') <> 1
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
