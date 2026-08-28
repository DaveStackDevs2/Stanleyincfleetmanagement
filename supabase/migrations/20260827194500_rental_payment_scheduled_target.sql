-- Rental payment coverage target correction.
-- A normal Rental can be paid in advance through its scheduled Expected Return.
-- Once the Rental is overdue, the payment target advances with current elapsed billing time.
-- Paying never changes the reservation schedule and never creates an Extension.

CREATE OR REPLACE FUNCTION public.rental_payment_target_state(
  p_transportation_event_id uuid,
  p_effective_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_reservation public.reservations%rowtype;
  v_event public.transportation_events%rowtype;
  v_target_at timestamptz;
  v_charge jsonb;
BEGIN
  IF p_transportation_event_id IS NULL OR p_effective_at IS NULL THEN
    RAISE EXCEPTION 'Transportation event and effective timestamp are required' USING ERRCODE='22023';
  END IF;

  SELECT r.* INTO v_reservation
  FROM public.reservations r
  WHERE r.transportation_event_id=p_transportation_event_id
    AND lower(btrim(coalesce(r.reservation_type,'')))='rental'
  ORDER BY r.created_at,r.id
  LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rental reservation was not found' USING ERRCODE='P0002'; END IF;

  SELECT te.* INTO v_event
  FROM public.transportation_events te
  WHERE te.id=p_transportation_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transportation event was not found' USING ERRCODE='P0002'; END IF;

  v_target_at:=greatest(
    p_effective_at,
    coalesce(v_event.expected_return_at,v_reservation.expected_return_datetime,p_effective_at)
  );
  v_charge:=public.rental_charge_through_state(p_transportation_event_id,v_target_at);

  RETURN jsonb_build_object(
    'status','rental_payment_target_ready',
    'effective_at',p_effective_at,
    'payment_target_at',v_target_at,
    'payment_target_subtotal',v_charge->>'subtotal',
    'payment_target_tax',v_charge->>'tax',
    'payment_target_total',v_charge->>'total'
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.preview_rental_payment_amount_state(
  p_transportation_event_id uuid,
  p_payment_amount numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid;
  v_existing_paid numeric;
  v_effective_at timestamptz:=clock_timestamp();
  v_target jsonb;
  v_target_at timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_balance numeric;
BEGIN
  SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.v_user_effective_permissions WHERE user_id=v_user AND permission_key='billing.case_start') THEN
    RAISE EXCEPTION 'Billing payment permission is required' USING ERRCODE='42501';
  END IF;
  IF p_payment_amount IS NULL OR p_payment_amount<=0 OR p_payment_amount::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero' USING ERRCODE='22023';
  END IF;

  v_target:=public.rental_payment_target_state(p_transportation_event_id,v_effective_at);
  v_target_at:=(v_target->>'payment_target_at')::timestamptz;
  v_existing_paid:=public.rental_recorded_payment_total_state(p_transportation_event_id);
  v_before:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid,v_target_at);
  v_balance:=(v_before->>'balance_due')::numeric;
  IF p_payment_amount>v_balance THEN
    RAISE EXCEPTION 'Payment amount exceeds the scheduled/current Rental balance' USING ERRCODE='22023';
  END IF;
  v_after:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid+p_payment_amount,v_target_at);

  RETURN jsonb_build_object(
    'status','rental_payment_amount_preview_ready',
    'effective_at',v_effective_at,
    'payment_target_at',v_target_at,
    'payment_amount',p_payment_amount::text,
    'already_paid',v_existing_paid::text,
    'paid_total_after',v_after->>'paid_total',
    'paid_through_after',v_after->'paid_through_at',
    'paid_days_after',(v_after->>'paid_charge_days')::integer,
    'remaining_days_after',(v_after->>'owed_charge_days')::integer,
    'remaining_amount_after',v_after->>'balance_due',
    'partial_credit_after',v_after->>'partial_credit',
    'current_total',v_after->>'current_total'
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.preview_rental_payment_through_state(
  p_transportation_event_id uuid,
  p_paid_through_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid;
  v_existing_paid numeric;
  v_effective_at timestamptz:=clock_timestamp();
  v_payment_target jsonb;
  v_payment_target_at timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_target jsonb;
  v_target_total numeric;
  v_planned_total numeric;
  v_required numeric;
BEGIN
  SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.v_user_effective_permissions WHERE user_id=v_user AND permission_key='billing.case_start') THEN
    RAISE EXCEPTION 'Billing payment permission is required' USING ERRCODE='42501';
  END IF;
  IF p_paid_through_at IS NULL THEN
    RAISE EXCEPTION 'Paid Through is required' USING ERRCODE='22023';
  END IF;

  v_payment_target:=public.rental_payment_target_state(p_transportation_event_id,v_effective_at);
  v_payment_target_at:=(v_payment_target->>'payment_target_at')::timestamptz;
  IF p_paid_through_at>v_payment_target_at THEN
    RAISE EXCEPTION 'Paid Through cannot exceed the current scheduled Rental return/payment target' USING ERRCODE='22023';
  END IF;

  v_existing_paid:=public.rental_recorded_payment_total_state(p_transportation_event_id);
  v_before:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid,v_payment_target_at);
  v_planned_total:=(v_before->>'current_total')::numeric;
  v_target:=public.rental_charge_through_state(p_transportation_event_id,p_paid_through_at);
  v_target_total:=(v_target->>'total')::numeric;
  v_required:=greatest(least(v_target_total,v_planned_total)-v_existing_paid,0);
  v_after:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid+v_required,v_payment_target_at);

  RETURN jsonb_build_object(
    'status','rental_payment_through_preview_ready',
    'effective_at',v_effective_at,
    'payment_target_at',v_payment_target_at,
    'requested_paid_through_at',p_paid_through_at,
    'payment_amount',v_required::text,
    'already_paid',v_existing_paid::text,
    'paid_total_after',v_after->>'paid_total',
    'paid_through_after',v_after->'paid_through_at',
    'paid_days_after',(v_after->>'paid_charge_days')::integer,
    'remaining_days_after',(v_after->>'owed_charge_days')::integer,
    'remaining_amount_after',v_after->>'balance_due',
    'partial_credit_after',v_after->>'partial_credit',
    'current_total',v_after->>'current_total'
  );
END
$function$;

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
  v_payment_target jsonb;
  v_payment_target_at timestamptz;
  v_total_paid numeric;
  v_progress jsonb;
  v_payments jsonb;
BEGIN
  SELECT id INTO v_actor FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501'; END IF;

  v_base:=public.get_rental_payment_state(p_transportation_event_id);
  IF v_base->>'status' IS DISTINCT FROM 'rental_payment_state_ready' THEN RETURN v_base; END IF;

  SELECT r.* INTO v_reservation
  FROM public.reservations r
  WHERE r.transportation_event_id=p_transportation_event_id
    AND lower(btrim(coalesce(r.reservation_type,'')))='rental'
  ORDER BY r.created_at,r.id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rental reservation was not found' USING ERRCODE='P0002'; END IF;

  SELECT a.* INTO v_agreement
  FROM public.rental_pricing_agreements a
  WHERE a.reservation_id=v_reservation.id
    AND a.transportation_event_id=p_transportation_event_id
    AND a.is_active=true
  ORDER BY a.updated_at DESC,a.id DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active Rental pricing agreement was not found' USING ERRCODE='P0002'; END IF;

  v_reserved_start:=v_reservation.start_date;
  v_billing_start:=coalesce(v_agreement.pricing_started_at,v_reserved_start);
  v_effective_at:=(v_base->>'effective_at')::timestamptz;
  SELECT min(ve.actual_out_at) INTO v_actual_out
  FROM public.vehicle_events ve
  WHERE ve.transportation_event_id=p_transportation_event_id AND ve.actual_out_at IS NOT NULL;

  v_payment_target:=public.rental_payment_target_state(p_transportation_event_id,v_effective_at);
  v_payment_target_at:=(v_payment_target->>'payment_target_at')::timestamptz;
  v_total_paid:=public.rental_recorded_payment_total_state(p_transportation_event_id);
  v_progress:=public.rental_payment_progress_state(p_transportation_event_id,v_total_paid,v_payment_target_at);

  SELECT coalesce(jsonb_agg(x.payment ORDER BY x.payment_at,x.sort_id),'[]'::jsonb) INTO v_payments
  FROM (
    SELECT e.payment_at,e.id::text sort_id,jsonb_build_object(
      'payment_id',e.id,
      'source_type','payment_entry',
      'amount',e.amount::text,
      'payment_at',e.payment_at,
      'reference_type',e.reference_type,
      'reference_number',e.reference_number,
      'reference_missing',e.reference_number IS NULL,
      'paid_through_after',e.paid_through_after,
      'paid_days_after',e.paid_days_after,
      'remaining_days_after',e.remaining_days_after,
      'remaining_amount_after',e.remaining_amount_after::text,
      'partial_credit_after',e.partial_credit_after::text
    ) payment
    FROM public.rental_payment_entries e
    WHERE e.transportation_event_id=p_transportation_event_id
    UNION ALL
    SELECT coalesce(b.rental_paid_at,b.updated_at),b.id::text,jsonb_build_object(
      'payment_id',b.id,
      'source_type','legacy_billing_line',
      'amount',(coalesce(b.amount,0)+coalesce(b.tax_amount,0))::text,
      'payment_at',coalesce(b.rental_paid_at,b.updated_at),
      'reference_type',b.rental_payment_reference_type,
      'reference_number',b.rental_payment_reference_number,
      'reference_missing',nullif(btrim(b.rental_payment_reference_number),'') IS NULL,
      'paid_through_after',b.paid_through_at,
      'paid_days_after',NULL,
      'remaining_days_after',NULL,
      'remaining_amount_after',NULL,
      'partial_credit_after',NULL
    )
    FROM public.billing_lines b
    WHERE b.transportation_event_id=p_transportation_event_id
      AND b.parent_billing_line_id IS NULL
      AND b.line_type IN ('initial_assignment','rental_extension')
      AND b.rental_paid_in_full
      AND NOT EXISTS (SELECT 1 FROM public.rental_payment_entries e WHERE e.legacy_billing_line_id=b.id)
  ) x;

  RETURN v_base || jsonb_build_object(
    'reserved_start_at',v_reserved_start,
    'billing_start_at',v_billing_start,
    'actual_out_at',v_actual_out,
    'payment_target_at',v_payment_target_at,
    'payment_target_total',v_progress->>'current_total',
    'paid_total',v_progress->>'paid_total',
    'balance_due',v_progress->>'balance_due',
    'current_balance_paid_in_full',(v_progress->>'balance_due')::numeric=0,
    'total_charge_days',coalesce(public.rental_pricing_days(v_billing_start,v_payment_target_at),0),
    'paid_charge_days',(v_progress->>'paid_charge_days')::integer,
    'owed_charge_days',(v_progress->>'owed_charge_days')::integer,
    'paid_through_at',v_progress->'paid_through_at',
    'overall_paid_in_full',(v_progress->>'balance_due')::numeric=0,
    'partial_credit',v_progress->>'partial_credit',
    'credit_balance',v_progress->>'credit_balance',
    'payments',v_payments
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.rental_payment_warning_rows()
RETURNS TABLE(
  item_type text,
  source_id uuid,
  reservation_id uuid,
  vehicle_id uuid,
  risk_level text,
  source_status text,
  expected_return_snapshot timestamptz,
  contract_period_id uuid,
  reminder_state text,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_row record;
  v_target jsonb;
  v_target_total numeric;
  v_paid numeric;
BEGIN
  SELECT id INTO v_actor FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501'; END IF;

  FOR v_row IN
    SELECT te.id event_id,r.id reservation_id,te.status,te.expected_return_at,
      (SELECT min(b.vehicle_id::text)::uuid FROM public.billing_lines b WHERE b.transportation_event_id=te.id AND b.parent_billing_line_id IS NULL) vehicle_id
    FROM public.transportation_events te
    JOIN public.reservations r ON r.transportation_event_id=te.id
    WHERE lower(btrim(coalesce(r.reservation_type,'')))='rental' AND lower(btrim(coalesce(te.status,'')))='active'
  LOOP
    v_target:=public.rental_payment_target_state(v_row.event_id,clock_timestamp());
    v_target_total:=(v_target->>'payment_target_total')::numeric;
    v_paid:=public.rental_recorded_payment_total_state(v_row.event_id);
    IF v_target_total>v_paid THEN
      item_type:='unpaid_rental';source_id:=v_row.event_id;reservation_id:=v_row.reservation_id;vehicle_id:=v_row.vehicle_id;
      risk_level:=NULL;source_status:=v_row.status;expected_return_snapshot:=v_row.expected_return_at;contract_period_id:=NULL;reminder_state:=NULL;
      message:='Rental has an unpaid balance. Balance Due: $'||(v_target_total-v_paid)::text;
      RETURN NEXT;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT 'rental_payment_reference_missing'::text,e.transportation_event_id,e.reservation_id,
    (SELECT min(b.vehicle_id::text)::uuid FROM public.billing_lines b WHERE b.transportation_event_id=e.transportation_event_id AND b.parent_billing_line_id IS NULL),
    NULL::text,te.status,te.expected_return_at,NULL::uuid,NULL::text,
    ('Rental payment of $'||e.amount::text||' is missing an SO#/RO# reference.')::text
  FROM public.rental_payment_entries e
  JOIN public.transportation_events te ON te.id=e.transportation_event_id
  WHERE nullif(btrim(e.reference_number),'') IS NULL;

  RETURN QUERY
  SELECT 'rental_payment_reference_missing'::text,b.transportation_event_id,b.reservation_id,b.vehicle_id,NULL::text,te.status,te.expected_return_at,NULL::uuid,NULL::text,
    (CASE WHEN b.line_type='rental_extension' THEN 'Rental Extension payment' ELSE 'Original Rental payment' END||' is missing an SO#/RO# reference.')::text
  FROM public.billing_lines b
  JOIN public.transportation_events te ON te.id=b.transportation_event_id
  WHERE b.parent_billing_line_id IS NULL
    AND b.line_type IN ('initial_assignment','rental_extension')
    AND b.rental_paid_in_full
    AND nullif(btrim(b.rental_payment_reference_number),'') IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.rental_payment_entries e WHERE e.legacy_billing_line_id=b.id);
END
$function$;

ALTER FUNCTION public.rental_payment_target_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) OWNER TO postgres;
ALTER FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_rental_payment_staff_state(uuid) OWNER TO postgres;
ALTER FUNCTION public.rental_payment_warning_rows() OWNER TO postgres;

REVOKE ALL ON FUNCTION public.rental_payment_target_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.get_rental_payment_staff_state(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_rental_payment_staff_state(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rental_payment_warning_rows() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rental_payment_warning_rows() TO authenticated;

COMMENT ON FUNCTION public.rental_payment_target_state(uuid,timestamptz) IS
  'Resolves the Rental payment coverage target: scheduled Expected Return while ahead, otherwise the effective current time.';
COMMENT ON FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) IS
  'Previews a Rental payment amount against the scheduled/current payment target and returns authoritative Paid Through, paid/owed days, partial credit, and remaining balance.';
COMMENT ON FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) IS
  'Previews exact Rental payment needed through a requested point, up to scheduled Expected Return while ahead or current elapsed time when overdue.';
