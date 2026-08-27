-- Rental Billing second-pass workflow.
-- Reserved schedule remains authoritative reservation history.
-- pricing_started_at is the active Rental Billing Start and is changed only by an explicit staff action.
-- Actual pickup remains a separate vehicle-use fact and never changes billing or expected return automatically.

CREATE OR REPLACE FUNCTION public.get_rental_payment_staff_state(p_transportation_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_base jsonb;
  v_reservation public.reservations%rowtype;
  v_agreement public.rental_pricing_agreements%rowtype;
  v_reserved_start timestamptz;
  v_billing_start timestamptz;
  v_actual_out timestamptz;
  v_effective_at timestamptz;
  v_paid_through timestamptz;
  v_total_days integer := 0;
  v_paid_days integer := 0;
  v_owed_days integer := 0;
  v_all_paid boolean := true;
  v_contiguous boolean := true;
  v_row record;
BEGIN
  SELECT id INTO v_actor
  FROM public.app_users
  WHERE auth_user_id = auth.uid() AND is_active = true;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501';
  END IF;

  v_base := public.get_rental_payment_state(p_transportation_event_id);
  IF v_base->>'status' IS DISTINCT FROM 'rental_payment_state_ready' THEN
    RETURN v_base;
  END IF;

  SELECT r.* INTO v_reservation
  FROM public.reservations r
  WHERE r.transportation_event_id = p_transportation_event_id
    AND lower(btrim(coalesce(r.reservation_type,''))) = 'rental'
  ORDER BY r.created_at,r.id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Rental reservation was not found' USING ERRCODE='P0002';
  END IF;

  SELECT a.* INTO v_agreement
  FROM public.rental_pricing_agreements a
  WHERE a.reservation_id = v_reservation.id
    AND a.transportation_event_id = p_transportation_event_id
    AND a.is_active = true
  ORDER BY a.updated_at DESC,a.id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active Rental pricing agreement was not found' USING ERRCODE='P0002';
  END IF;

  v_reserved_start := v_reservation.start_date;
  v_billing_start := coalesce(v_agreement.pricing_started_at,v_reserved_start);
  v_effective_at := (v_base->>'effective_at')::timestamptz;

  SELECT min(ve.actual_out_at) INTO v_actual_out
  FROM public.vehicle_events ve
  WHERE ve.transportation_event_id = p_transportation_event_id
    AND ve.actual_out_at IS NOT NULL;

  FOR v_row IN
    SELECT b.*
    FROM public.billing_lines b
    WHERE b.transportation_event_id = p_transportation_event_id
      AND b.reservation_id = v_reservation.id
      AND b.parent_billing_line_id IS NULL
      AND b.line_type IN ('initial_assignment','rental_extension')
    ORDER BY b.start_time,b.created_at,b.id
  LOOP
    IF btrim(coalesce(v_row.amount,0)::text) IS NULL THEN
      NULL;
    END IF;

    IF v_row.rental_paid_in_full OR (coalesce(v_row.amount,0)+coalesce(v_row.tax_amount,0)=0) THEN
      IF v_contiguous THEN
        v_paid_through := coalesce(v_row.paid_through_at,v_row.end_time,v_paid_through);
      END IF;
    ELSE
      v_all_paid := false;
      v_contiguous := false;
    END IF;
  END LOOP;

  v_total_days := coalesce(public.rental_pricing_days(v_billing_start,v_effective_at),0);
  IF v_paid_through IS NOT NULL AND v_paid_through > v_billing_start THEN
    v_paid_days := coalesce(public.rental_pricing_days(v_billing_start,v_paid_through),0);
  END IF;
  v_owed_days := greatest(v_total_days-v_paid_days,0);

  RETURN v_base || jsonb_build_object(
    'reserved_start_at',v_reserved_start,
    'billing_start_at',v_billing_start,
    'actual_out_at',v_actual_out,
    'total_charge_days',v_total_days,
    'paid_charge_days',v_paid_days,
    'owed_charge_days',v_owed_days,
    'paid_through_at',v_paid_through,
    'overall_paid_in_full',v_all_paid
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.set_rental_billing_start_state(
  p_reservation_id uuid,
  p_billing_start_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid;
  v_reservation public.reservations%rowtype;
  v_event public.transportation_events%rowtype;
  v_agreement public.rental_pricing_agreements%rowtype;
  v_original public.billing_lines%rowtype;
  v_old_start timestamptz;
  v_segment_end timestamptz;
  v_days integer;
  v_price jsonb;
  v_tax jsonb;
  v_tax_child jsonb;
  v_subtotal numeric;
  v_tax_amount numeric;
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
    RAISE EXCEPTION 'Billing case-start permission is required' USING ERRCODE='42501';
  END IF;
  IF p_billing_start_at IS NULL THEN
    RAISE EXCEPTION 'Billing start is required' USING ERRCODE='22023';
  END IF;

  SELECT r.* INTO v_reservation
  FROM public.reservations r
  WHERE r.id=p_reservation_id
  FOR UPDATE;

  IF NOT FOUND OR lower(btrim(coalesce(v_reservation.reservation_type,''))) <> 'rental' THEN
    RAISE EXCEPTION 'Active Rental reservation was not found' USING ERRCODE='P0002';
  END IF;

  SELECT te.* INTO v_event
  FROM public.transportation_events te
  WHERE te.id=v_reservation.transportation_event_id
  FOR UPDATE;

  IF NOT FOUND OR lower(btrim(coalesce(v_event.status,''))) <> 'active' OR v_reservation.actual_return_datetime IS NOT NULL THEN
    RAISE EXCEPTION 'Rental Billing Start can only be changed on an active Rental' USING ERRCODE='P0001';
  END IF;

  SELECT a.* INTO v_agreement
  FROM public.rental_pricing_agreements a
  WHERE a.reservation_id=v_reservation.id
    AND a.transportation_event_id=v_reservation.transportation_event_id
    AND a.is_active=true
  ORDER BY a.updated_at DESC,a.id DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND OR v_agreement.pricing_started_at IS NULL THEN
    RAISE EXCEPTION 'Rental has not started Billing' USING ERRCODE='P0001';
  END IF;

  SELECT b.* INTO v_original
  FROM public.billing_lines b
  WHERE b.reservation_id=v_reservation.id
    AND b.transportation_event_id=v_reservation.transportation_event_id
    AND b.parent_billing_line_id IS NULL
    AND b.line_type='initial_assignment'
  ORDER BY b.created_at,b.id
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original Rental billing period was not found' USING ERRCODE='P0002';
  END IF;

  v_old_start := v_agreement.pricing_started_at;
  v_segment_end := coalesce(v_original.end_time,v_event.expected_return_at,v_reservation.expected_return_datetime);

  IF p_billing_start_at < v_reservation.start_date THEN
    RAISE EXCEPTION 'Billing Start cannot precede the reserved start' USING ERRCODE='22023';
  END IF;
  IF p_billing_start_at > clock_timestamp() THEN
    RAISE EXCEPTION 'Billing Start cannot be in the future' USING ERRCODE='22023';
  END IF;
  IF v_segment_end IS NULL OR p_billing_start_at >= v_segment_end THEN
    RAISE EXCEPTION 'Billing Start must remain before the end of the Original Rental period' USING ERRCODE='22023';
  END IF;

  v_days := public.rental_pricing_days(p_billing_start_at,v_segment_end);
  v_price := public.resolve_rental_block_pricing_state(
    v_days,
    v_agreement.daily_rate_snapshot,
    v_agreement.weekly_rate_snapshot,
    v_agreement.monthly_rate_snapshot
  );
  v_subtotal := (v_price->>'subtotal')::numeric;
  v_tax := public.resolve_billing_tax_state(coalesce(v_original.pay_type,v_reservation.pay_type),v_subtotal);
  v_tax_amount := (v_tax->>'tax_amount')::numeric;

  UPDATE public.rental_pricing_agreements
  SET pricing_started_at=p_billing_start_at,
      updated_by=v_user,
      updated_at=clock_timestamp()
  WHERE id=v_agreement.id;

  UPDATE public.billing_lines
  SET start_time=p_billing_start_at,
      amount=v_subtotal,
      tax_amount=v_tax_amount,
      rental_block_pricing_snapshot=v_price,
      updated_at=clock_timestamp()
  WHERE id=v_original.id;

  v_tax_child := public.ensure_tax_child_line_state(v_original.id);

  INSERT INTO public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata)
  VALUES (
    'transportation_event',v_reservation.transportation_event_id::text,
    'rental_billing_start_adjusted','billing_start',v_old_start::text,p_billing_start_at::text,v_user::text,
    jsonb_build_object(
      'reservation_id',v_reservation.id,
      'original_reserved_start',v_reservation.start_date,
      'expected_return_unchanged',coalesce(v_event.expected_return_at,v_reservation.expected_return_datetime),
      'original_billing_line_id',v_original.id,
      'original_period_days',v_days,
      'original_period_subtotal',v_subtotal,
      'original_period_tax',v_tax_amount
    )
  );

  RETURN public.get_rental_payment_staff_state(v_reservation.transportation_event_id);
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
    AND (coalesce(b.amount,0)+coalesce(b.tax_amount,0)) > 0
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

ALTER FUNCTION public.get_rental_payment_staff_state(uuid) OWNER TO postgres;
ALTER FUNCTION public.set_rental_billing_start_state(uuid,timestamptz) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.get_rental_payment_staff_state(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_rental_payment_staff_state(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.set_rental_billing_start_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_rental_billing_start_state(uuid,timestamptz) TO authenticated;

COMMENT ON FUNCTION public.get_rental_payment_staff_state(uuid) IS
  'Staff Rental payment view: preserves reserved start and actual pickup as separate facts, uses pricing_started_at as Billing Start, and treats zero-dollar periods as settled without payment.';
COMMENT ON FUNCTION public.set_rental_billing_start_state(uuid,timestamptz) IS
  'Explicitly adjusts active Rental Billing Start without changing reservation start, expected return, or actual pickup; reprices only the Original Rental period and audits the change.';