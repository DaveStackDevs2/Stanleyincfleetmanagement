-- Rental Billing workflow UX support. Data-free except for nullable metadata columns.
-- Customer-facing Rental days round any partial 24-hour period up to the next whole day.
-- Payment references are optional at payment time; missing references remain a Warning Center condition until resolved.

ALTER TABLE public.billing_lines
  ADD COLUMN IF NOT EXISTS rental_payment_reference_type text,
  ADD COLUMN IF NOT EXISTS rental_payment_reference_number text;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ck_billing_lines_rental_payment_reference'
      AND conrelid = 'public.billing_lines'::regclass
  ) THEN
    ALTER TABLE public.billing_lines
      ADD CONSTRAINT ck_billing_lines_rental_payment_reference
      CHECK (
        (rental_payment_reference_type IS NULL AND rental_payment_reference_number IS NULL)
        OR (
          rental_paid_in_full
          AND rental_payment_reference_type IN ('SO','RO')
          AND nullif(btrim(rental_payment_reference_number),'') IS NOT NULL
        )
      );
  END IF;
END
$migration$;

COMMENT ON COLUMN public.billing_lines.rental_payment_reference_type IS
  'Optional Rental payment proof type: SO or RO. A paid line may remain null and surface a Warning Center item.';
COMMENT ON COLUMN public.billing_lines.rental_payment_reference_number IS
  'Optional Rental payment proof number. Missing on a paid line is a resolvable Warning Center condition, not a payment blocker.';

CREATE OR REPLACE FUNCTION public.rental_pricing_days(
  p_segment_start timestamptz,
  p_segment_end timestamptz
) RETURNS integer
LANGUAGE sql STABLE
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN p_segment_start IS NULL OR p_segment_end IS NULL THEN NULL
    WHEN p_segment_end < p_segment_start THEN NULL
    WHEN p_segment_end = p_segment_start THEN 0
    ELSE ceil(extract(epoch FROM (p_segment_end - p_segment_start)) / 86400.0)::integer
  END
$function$;

COMMENT ON FUNCTION public.rental_pricing_days(timestamptz,timestamptz) IS
  'Authoritative Rental pricing-day boundary: any partial 24-hour period is charged as the next whole day; Loaner/EW inclusive business_contract_days semantics are unchanged.';

CREATE OR REPLACE FUNCTION public.get_rental_payment_state(p_transportation_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_reservation uuid;
  v_rental_start timestamptz;
  v_expected_return timestamptz;
  v_preview jsonb;
  v_preview_ready boolean := false;
  v_current_line_id uuid;
  v_effective_at timestamptz := clock_timestamp();
  v_lines jsonb := '[]'::jsonb;
  v_row record;
  v_line_days integer;
  v_line_block jsonb;
  v_line_paid_through timestamptz;
  v_contract_charge numeric := 0;
  v_contract_tax numeric := 0;
  v_unpaid_charge numeric := 0;
  v_unpaid_tax numeric := 0;
  v_paid_charge numeric := 0;
  v_paid_tax numeric := 0;
  v_all_paid boolean := true;
  v_any_line boolean := false;
  v_contiguous_paid boolean := true;
  v_paid_through timestamptz;
  v_paid_days integer := 0;
  v_total_days integer := 0;
  v_current_charge numeric := 0;
  v_current_tax numeric := 0;
  v_current_total numeric := 0;
  v_balance_due numeric := 0;
  v_owed_days integer := 0;
  v_overdue_days integer := 0;
BEGIN
  SELECT id INTO v_actor
  FROM public.app_users
  WHERE auth_user_id = auth.uid() AND is_active = true;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'An active application user is required' USING ERRCODE = '42501';
  END IF;

  SELECT r.id, r.start_date, coalesce(te.expected_return_at,r.expected_return_datetime)
  INTO v_reservation, v_rental_start, v_expected_return
  FROM public.reservations r
  JOIN public.transportation_events te ON te.id = r.transportation_event_id
  WHERE r.transportation_event_id = p_transportation_event_id
    AND lower(coalesce(r.reservation_type,'')) LIKE '%rental%'
  ORDER BY r.created_at
  LIMIT 1;

  IF v_reservation IS NULL THEN
    RAISE EXCEPTION 'Rental case was not found' USING ERRCODE = 'P0002';
  END IF;

  v_preview := public.get_billing_preview_state(p_transportation_event_id,v_effective_at);
  v_preview_ready := v_preview->>'status' = 'billing_preview_ready';

  IF v_preview_ready AND nullif(v_preview->>'current_billing_line_id','') IS NOT NULL THEN
    BEGIN
      v_current_line_id := (v_preview->>'current_billing_line_id')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      v_current_line_id := NULL;
    END;
  END IF;

  FOR v_row IN
    SELECT b.*
    FROM public.billing_lines b
    WHERE b.transportation_event_id = p_transportation_event_id
      AND b.reservation_id = v_reservation
      AND b.parent_billing_line_id IS NULL
      AND b.line_type IN ('initial_assignment','rental_extension')
    ORDER BY b.start_time,b.created_at,b.id
  LOOP
    v_any_line := true;
    v_contract_charge := v_contract_charge + coalesce(v_row.amount,0);
    v_contract_tax := v_contract_tax + coalesce(v_row.tax_amount,0);

    v_line_block := v_row.rental_block_pricing_snapshot;
    v_line_days := CASE
      WHEN v_line_block IS NOT NULL AND nullif(v_line_block->>'segment_days','') IS NOT NULL
        THEN (v_line_block->>'segment_days')::integer
      ELSE public.rental_pricing_days(v_row.start_time,v_row.end_time)
    END;
    v_line_days := coalesce(v_line_days,0);

    IF v_row.rental_paid_in_full THEN
      v_paid_charge := v_paid_charge + coalesce(v_row.amount,0);
      v_paid_tax := v_paid_tax + coalesce(v_row.tax_amount,0);
      v_line_paid_through := coalesce(v_row.paid_through_at,v_row.end_time);
      IF v_contiguous_paid THEN
        v_paid_through := v_line_paid_through;
      END IF;
    ELSE
      v_unpaid_charge := v_unpaid_charge + coalesce(v_row.amount,0);
      v_unpaid_tax := v_unpaid_tax + coalesce(v_row.tax_amount,0);
      v_all_paid := false;
      v_contiguous_paid := false;
      v_line_paid_through := NULL;
    END IF;

    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'billing_line_id',v_row.id,
      'purpose',CASE WHEN v_row.line_type='rental_extension' THEN 'Rental Extension' ELSE 'Original Rental' END,
      'line_type',v_row.line_type,
      'start_at',v_row.start_time,
      'through_at',v_row.end_time,
      'charge_days',v_line_days,
      'block_pricing',v_line_block,
      'charge',coalesce(v_row.amount,0)::text,
      'tax',coalesce(v_row.tax_amount,0)::text,
      'total',(coalesce(v_row.amount,0)+coalesce(v_row.tax_amount,0))::text,
      'rental_paid_in_full',v_row.rental_paid_in_full,
      'payment_status',CASE WHEN v_row.rental_paid_in_full THEN 'Paid' ELSE 'Not Paid' END,
      'rental_paid_at',v_row.rental_paid_at,
      'payment_paid_through_at',v_line_paid_through,
      'payment_reference_type',v_row.rental_payment_reference_type,
      'payment_reference_number',v_row.rental_payment_reference_number,
      'payment_reference_missing',v_row.rental_paid_in_full AND nullif(btrim(v_row.rental_payment_reference_number),'') IS NULL
    ));
  END LOOP;

  IF NOT v_any_line THEN
    v_all_paid := true;
  END IF;

  v_total_days := coalesce(public.rental_pricing_days(v_rental_start,v_effective_at),0);
  IF v_paid_through IS NOT NULL THEN
    v_paid_days := coalesce(public.rental_pricing_days(v_rental_start,v_paid_through),0);
  END IF;

  IF v_preview_ready THEN
    v_current_charge := (v_preview->>'accumulated_subtotal')::numeric;
    v_current_tax := (v_preview->>'accumulated_tax')::numeric;
    v_current_total := (v_preview->>'accumulated_total')::numeric;
  ELSE
    v_current_charge := v_contract_charge;
    v_current_tax := v_contract_tax;
    v_current_total := v_contract_charge + v_contract_tax;
  END IF;

  v_balance_due := greatest(v_current_total - (v_paid_charge + v_paid_tax),0);
  v_owed_days := greatest(v_total_days - v_paid_days,0);

  IF v_expected_return IS NOT NULL AND v_effective_at > v_expected_return THEN
    v_overdue_days := coalesce(public.rental_pricing_days(v_expected_return,v_effective_at),0);
  END IF;

  RETURN jsonb_build_object(
    'status','rental_payment_state_ready',
    'reservation_id',v_reservation,
    'transportation_event_id',p_transportation_event_id,
    'effective_at',v_effective_at,
    'lines',v_lines,
    'contractual_charge',v_contract_charge::text,
    'contractual_tax',v_contract_tax::text,
    'contractual_total',(v_contract_charge+v_contract_tax)::text,
    'unpaid_charge',v_unpaid_charge::text,
    'unpaid_tax',v_unpaid_tax::text,
    'unpaid_total',(v_unpaid_charge+v_unpaid_tax)::text,
    'overall_paid_in_full',v_all_paid,
    'current_preview_ready',v_preview_ready,
    'current_charge',v_current_charge::text,
    'current_tax',v_current_tax::text,
    'current_total',v_current_total::text,
    'paid_charge',v_paid_charge::text,
    'paid_tax',v_paid_tax::text,
    'paid_total',(v_paid_charge+v_paid_tax)::text,
    'balance_due',v_balance_due::text,
    'current_balance_paid_in_full',v_balance_due=0,
    'total_charge_days',v_total_days,
    'paid_charge_days',v_paid_days,
    'owed_charge_days',v_owed_days,
    'paid_through_at',v_paid_through,
    'expected_return_at',v_expected_return,
    'overdue_days',v_overdue_days,
    'current_block_pricing',CASE WHEN v_preview_ready THEN v_preview->'rental_block_pricing' ELSE NULL END
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.record_rental_billing_line_payment_state(
  p_billing_line_id uuid,
  p_reference_type text DEFAULT NULL,
  p_reference_number text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid;
  v_line public.billing_lines%rowtype;
  v_reference_type text;
  v_reference_number text;
  v_was_paid boolean;
  v_old_reference_type text;
  v_old_reference_number text;
BEGIN
  SELECT id INTO v_user
  FROM public.app_users
  WHERE auth_user_id=auth.uid() AND is_active=true;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501';
  END IF;
  IF coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN
    RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.v_user_effective_permissions
    WHERE user_id=v_user AND permission_key='billing.case_start'
  ) THEN
    RAISE EXCEPTION 'Billing payment permission is required' USING ERRCODE='42501';
  END IF;

  v_reference_number := nullif(btrim(p_reference_number),'');
  IF v_reference_number IS NULL THEN
    v_reference_type := NULL;
  ELSE
    v_reference_type := upper(btrim(coalesce(p_reference_type,'')));
    IF v_reference_type NOT IN ('SO','RO') THEN
      RAISE EXCEPTION 'Payment reference type must be SO or RO' USING ERRCODE='22023';
    END IF;
  END IF;

  SELECT b.* INTO v_line
  FROM public.billing_lines b
  JOIN public.reservations r ON r.id=b.reservation_id
  WHERE b.id=p_billing_line_id
    AND b.parent_billing_line_id IS NULL
    AND b.line_type IN ('initial_assignment','rental_extension')
    AND lower(coalesce(r.reservation_type,'')) LIKE '%rental%'
  FOR UPDATE OF b;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Eligible Rental parent billing line not found' USING ERRCODE='P0002';
  END IF;

  v_was_paid := v_line.rental_paid_in_full;
  v_old_reference_type := v_line.rental_payment_reference_type;
  v_old_reference_number := v_line.rental_payment_reference_number;

  UPDATE public.billing_lines
  SET rental_paid_in_full = true,
      rental_paid_at = CASE WHEN v_was_paid THEN rental_paid_at ELSE clock_timestamp() END,
      rental_paid_by_user_id = CASE WHEN v_was_paid THEN rental_paid_by_user_id ELSE v_user END,
      paid_through_at = CASE WHEN v_was_paid THEN paid_through_at ELSE coalesce(end_time,paid_through_at,clock_timestamp()) END,
      rental_payment_reference_type = CASE WHEN v_reference_number IS NULL THEN rental_payment_reference_type ELSE v_reference_type END,
      rental_payment_reference_number = CASE WHEN v_reference_number IS NULL THEN rental_payment_reference_number ELSE v_reference_number END,
      updated_at = clock_timestamp()
  WHERE id=v_line.id;

  IF NOT v_was_paid THEN
    INSERT INTO public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata)
    VALUES (
      'billing_line',v_line.id::text,'rental_paid_in_full_recorded','rental_paid_in_full','false','true',v_user::text,
      jsonb_build_object(
        'transportation_event_id',v_line.transportation_event_id,
        'reservation_id',v_line.reservation_id,
        'payment_reference_present',v_reference_number IS NOT NULL,
        'payment_reference_type',v_reference_type
      )
    );
  END IF;

  IF v_reference_number IS NOT NULL
     AND (v_old_reference_type IS DISTINCT FROM v_reference_type OR v_old_reference_number IS DISTINCT FROM v_reference_number) THEN
    INSERT INTO public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata)
    VALUES (
      'billing_line',v_line.id::text,'rental_payment_reference_recorded','rental_payment_reference',
      concat_ws(' ',v_old_reference_type,v_old_reference_number),concat_ws(' ',v_reference_type,v_reference_number),v_user::text,
      jsonb_build_object('transportation_event_id',v_line.transportation_event_id,'reservation_id',v_line.reservation_id)
    );
  END IF;

  RETURN public.get_rental_payment_state(v_line.transportation_event_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.mark_rental_billing_line_paid_in_full_state(p_billing_line_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  RETURN public.record_rental_billing_line_payment_state(p_billing_line_id,NULL,NULL);
END
$function$;

CREATE OR REPLACE VIEW public.v_warning_center_warning_items
WITH (security_invoker = true) AS
 SELECT 'dependency_warning'::text AS item_type,
    d.id AS source_id,
    d.reservation_id,
    d.vehicle_id,
    d.risk_level,
    d.status AS source_status,
    d.expected_return_snapshot,
    NULL::uuid AS contract_period_id,
    NULL::text AS reminder_state,
    'Dependency requires near-term attention'::text AS message
   FROM public.reservation_vehicle_dependencies d
  WHERE d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text])
    AND d.risk_level = ANY (ARRAY['at_risk'::text, 'must_return'::text])
UNION ALL
 SELECT 'contract_reminder'::text AS item_type,
    NULL::uuid AS source_id,
    NULL::uuid AS reservation_id,
    NULL::uuid AS vehicle_id,
    NULL::text AS risk_level,
    NULL::text AS source_status,
    NULL::timestamptz AS expected_return_snapshot,
    m.contract_period_id,
    m.reminder_state,
    'Contract/reminder action needed soon'::text AS message
   FROM public.v_contract_period_monitoring m
  WHERE m.reminder_state = ANY (ARRAY['renew_now'::text, 'swap_required'::text])
UNION ALL
 SELECT 'unpaid_rental'::text AS item_type,
    te.id AS source_id,
    r.id AS reservation_id,
    min(b.vehicle_id::text)::uuid AS vehicle_id,
    NULL::text AS risk_level,
    te.status AS source_status,
    te.expected_return_at AS expected_return_snapshot,
    NULL::uuid AS contract_period_id,
    NULL::text AS reminder_state,
    'Rental has an unpaid balance. Balance Due: $'::text || (sum(b.amount)+sum(coalesce(b.tax_amount,0)))::text AS message
   FROM public.transportation_events te
   JOIN public.reservations r ON r.transportation_event_id=te.id
   JOIN public.billing_lines b ON b.reservation_id=r.id
    AND b.parent_billing_line_id IS NULL
    AND b.line_type = ANY (ARRAY['initial_assignment'::text,'rental_extension'::text])
    AND NOT b.rental_paid_in_full
  WHERE lower(coalesce(r.reservation_type,'')) LIKE '%rental%'
    AND lower(btrim(te.status))='active'
  GROUP BY te.id,r.id,te.status,te.expected_return_at
UNION ALL
 SELECT 'rental_payment_reference_missing'::text AS item_type,
    te.id AS source_id,
    r.id AS reservation_id,
    b.vehicle_id,
    NULL::text AS risk_level,
    te.status AS source_status,
    te.expected_return_at AS expected_return_snapshot,
    NULL::uuid AS contract_period_id,
    NULL::text AS reminder_state,
    (CASE WHEN b.line_type='rental_extension' THEN 'Rental Extension payment' ELSE 'Original Rental payment' END || ' is missing an SO#/RO# reference.')::text AS message
   FROM public.billing_lines b
   JOIN public.reservations r ON r.id=b.reservation_id
   JOIN public.transportation_events te ON te.id=b.transportation_event_id
  WHERE lower(coalesce(r.reservation_type,'')) LIKE '%rental%'
    AND b.parent_billing_line_id IS NULL
    AND b.line_type = ANY (ARRAY['initial_assignment'::text,'rental_extension'::text])
    AND b.rental_paid_in_full
    AND nullif(btrim(b.rental_payment_reference_number),'') IS NULL;

ALTER FUNCTION public.rental_pricing_days(timestamptz,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_rental_payment_state(uuid) OWNER TO postgres;
ALTER FUNCTION public.record_rental_billing_line_payment_state(uuid,text,text) OWNER TO postgres;
ALTER FUNCTION public.mark_rental_billing_line_paid_in_full_state(uuid) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.rental_pricing_days(timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rental_pricing_days(timestamptz,timestamptz) TO service_role;

REVOKE ALL ON FUNCTION public.get_rental_payment_state(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_rental_payment_state(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.record_rental_billing_line_payment_state(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_rental_billing_line_payment_state(uuid,text,text) TO authenticated;

REVOKE ALL ON FUNCTION public.mark_rental_billing_line_paid_in_full_state(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_rental_billing_line_paid_in_full_state(uuid) TO authenticated;

COMMENT ON FUNCTION public.record_rental_billing_line_payment_state(uuid,text,text) IS
  'Records Rental payment without requiring an SO/RO reference. Missing proof remains visible through Warning Center until the paid line receives a reference.';