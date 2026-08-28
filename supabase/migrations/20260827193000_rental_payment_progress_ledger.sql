-- Rental payment progress ledger.
-- Supports amount-driven and Paid-Through-driven payment previews without changing Rental schedule facts.
-- Payments apply oldest-first across the authoritative Rental charge timeline; overdue time never becomes an Extension.

CREATE TABLE public.rental_payment_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transportation_event_id uuid NOT NULL REFERENCES public.transportation_events(id) ON DELETE RESTRICT,
  reservation_id uuid NOT NULL REFERENCES public.reservations(id) ON DELETE RESTRICT,
  amount numeric NOT NULL,
  payment_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  reference_type text,
  reference_number text,
  recorded_by_user_id uuid NOT NULL REFERENCES public.app_users(id) ON DELETE RESTRICT,
  paid_through_after timestamptz,
  paid_days_after integer,
  remaining_days_after integer,
  remaining_amount_after numeric,
  partial_credit_after numeric,
  legacy_billing_line_id uuid UNIQUE REFERENCES public.billing_lines(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_rental_payment_entries_amount CHECK (amount > 0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  CONSTRAINT ck_rental_payment_entries_reference CHECK (
    (reference_type IS NULL AND reference_number IS NULL)
    OR (reference_type IN ('SO','RO') AND nullif(btrim(reference_number),'') IS NOT NULL)
  ),
  CONSTRAINT ck_rental_payment_entries_snapshots CHECK (
    (paid_days_after IS NULL OR paid_days_after >= 0)
    AND (remaining_days_after IS NULL OR remaining_days_after >= 0)
    AND (remaining_amount_after IS NULL OR (remaining_amount_after >= 0 AND remaining_amount_after::text NOT IN ('NaN','Infinity','-Infinity')))
    AND (partial_credit_after IS NULL OR (partial_credit_after >= 0 AND partial_credit_after::text NOT IN ('NaN','Infinity','-Infinity')))
  )
);
ALTER TABLE public.rental_payment_entries OWNER TO postgres;
ALTER TABLE public.rental_payment_entries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.rental_payment_entries FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rental_payment_entries TO service_role;
CREATE INDEX idx_rental_payment_entries_event_time ON public.rental_payment_entries(transportation_event_id,payment_at,id);

CREATE OR REPLACE FUNCTION public.rental_recorded_payment_total_state(p_transportation_event_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    coalesce((SELECT sum(e.amount) FROM public.rental_payment_entries e WHERE e.transportation_event_id=p_transportation_event_id),0)
    + coalesce((
      SELECT sum(coalesce(b.amount,0)+coalesce(b.tax_amount,0))
      FROM public.billing_lines b
      WHERE b.transportation_event_id=p_transportation_event_id
        AND b.parent_billing_line_id IS NULL
        AND b.line_type IN ('initial_assignment','rental_extension')
        AND b.rental_paid_in_full
        AND NOT EXISTS (
          SELECT 1 FROM public.rental_payment_entries e WHERE e.legacy_billing_line_id=b.id
        )
    ),0)
$function$;

CREATE OR REPLACE FUNCTION public.rental_charge_through_state(
  p_transportation_event_id uuid,
  p_through_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_reservation public.reservations%rowtype;
  v_active_agreement public.rental_pricing_agreements%rowtype;
  v_line record;
  v_line_agreement public.rental_pricing_agreements%rowtype;
  v_billing_start timestamptz;
  v_segment_end timestamptz;
  v_days integer;
  v_price jsonb;
  v_daily numeric;
  v_weekly numeric;
  v_monthly numeric;
  v_tax_rate numeric;
  v_subtotal numeric := 0;
  v_tax numeric := 0;
  v_line_subtotal numeric;
  v_line_tax numeric;
BEGIN
  IF p_transportation_event_id IS NULL OR p_through_at IS NULL THEN
    RAISE EXCEPTION 'Transportation event and through timestamp are required' USING ERRCODE='22023';
  END IF;

  SELECT r.* INTO v_reservation
  FROM public.reservations r
  WHERE r.transportation_event_id=p_transportation_event_id
    AND lower(btrim(coalesce(r.reservation_type,'')))='rental'
  ORDER BY r.created_at,r.id
  LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rental reservation was not found' USING ERRCODE='P0002'; END IF;

  SELECT a.* INTO v_active_agreement
  FROM public.rental_pricing_agreements a
  WHERE a.reservation_id=v_reservation.id
    AND a.transportation_event_id=p_transportation_event_id
    AND a.is_active=true
  ORDER BY a.updated_at DESC,a.id DESC
  LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active Rental pricing agreement was not found' USING ERRCODE='P0002'; END IF;

  v_billing_start:=coalesce(v_active_agreement.pricing_started_at,v_reservation.start_date);
  IF v_billing_start IS NULL THEN RAISE EXCEPTION 'Rental Billing Start is unavailable' USING ERRCODE='P0002'; END IF;
  IF p_through_at <= v_billing_start THEN
    RETURN jsonb_build_object('status','rental_charge_through_ready','through_at',p_through_at,'subtotal','0','tax','0','total','0');
  END IF;

  FOR v_line IN
    SELECT b.*
    FROM public.billing_lines b
    WHERE b.transportation_event_id=p_transportation_event_id
      AND b.reservation_id=v_reservation.id
      AND b.parent_billing_line_id IS NULL
      AND b.line_type IN ('initial_assignment','rental_extension')
      AND b.start_time IS NOT NULL
    ORDER BY b.start_time,b.created_at,b.id
  LOOP
    IF p_through_at <= v_line.start_time THEN CONTINUE; END IF;

    IF NOT v_line.is_open AND v_line.end_time IS NOT NULL AND p_through_at >= v_line.end_time THEN
      v_subtotal:=v_subtotal+coalesce(v_line.amount,0);
      v_tax:=v_tax+coalesce(v_line.tax_amount,0);
      CONTINUE;
    END IF;

    v_segment_end:=p_through_at;
    IF NOT v_line.is_open AND v_line.end_time IS NOT NULL THEN
      v_segment_end:=least(v_segment_end,v_line.end_time);
    END IF;
    IF v_segment_end <= v_line.start_time THEN CONTINUE; END IF;
    IF NOT v_line.is_open AND coalesce(v_line.amount,0)+coalesce(v_line.tax_amount,0)=0 THEN CONTINUE; END IF;

    v_daily:=nullif(v_line.rental_block_pricing_snapshot#>>'{daily,per_day_rate}','')::numeric;
    v_weekly:=nullif(v_line.rental_block_pricing_snapshot#>>'{weekly,per_day_rate}','')::numeric;
    v_monthly:=nullif(v_line.rental_block_pricing_snapshot#>>'{monthly,per_day_rate}','')::numeric;

    IF v_daily IS NULL OR (v_weekly IS NULL AND v_monthly IS NULL) THEN
      SELECT a.* INTO v_line_agreement
      FROM public.rental_pricing_agreements a
      WHERE a.id=v_line.pricing_agreement_id
         OR (a.reservation_id=v_reservation.id AND a.transportation_event_id=p_transportation_event_id AND a.is_active=true)
      ORDER BY (a.id=v_line.pricing_agreement_id) DESC,a.updated_at DESC,a.id DESC
      LIMIT 1;
      IF FOUND THEN
        v_daily:=coalesce(v_daily,v_line_agreement.daily_rate_snapshot);
        v_weekly:=coalesce(v_weekly,v_line_agreement.weekly_rate_snapshot);
        v_monthly:=coalesce(v_monthly,v_line_agreement.monthly_rate_snapshot);
      END IF;
    END IF;

    v_daily:=coalesce(v_daily,v_line.daily_rate_override,v_line.default_daily_rate_snapshot,v_line.rate_amount_snapshot);
    IF v_daily IS NULL THEN RAISE EXCEPTION 'Rental pricing snapshot is unavailable for payment allocation' USING ERRCODE='P0002'; END IF;

    v_days:=public.rental_pricing_days(v_line.start_time,v_segment_end);
    v_price:=public.resolve_rental_block_pricing_state(v_days,v_daily,v_weekly,v_monthly);
    v_line_subtotal:=(v_price->>'subtotal')::numeric;
    v_tax_rate:=coalesce(v_line.tax_rate_snapshot,CASE WHEN coalesce(v_line.amount,0)<>0 THEN coalesce(v_line.tax_amount,0)/v_line.amount ELSE 0 END,0);
    v_line_tax:=CASE WHEN coalesce(v_line.is_taxable_snapshot,false) THEN v_line_subtotal*v_tax_rate ELSE 0 END;
    v_subtotal:=v_subtotal+v_line_subtotal;
    v_tax:=v_tax+v_line_tax;
  END LOOP;

  RETURN jsonb_build_object(
    'status','rental_charge_through_ready',
    'through_at',p_through_at,
    'subtotal',v_subtotal::text,
    'tax',v_tax::text,
    'total',(v_subtotal+v_tax)::text
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.rental_payment_progress_state(
  p_transportation_event_id uuid,
  p_total_paid numeric,
  p_effective_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_reservation public.reservations%rowtype;
  v_agreement public.rental_pricing_agreements%rowtype;
  v_preview jsonb;
  v_billing_start timestamptz;
  v_current_total numeric;
  v_balance_due numeric;
  v_credit_balance numeric;
  v_total_days integer;
  v_paid_days integer := 0;
  v_owed_days integer := 0;
  v_paid_through timestamptz;
  v_charge_at_paid_through numeric := 0;
  v_partial_credit numeric := 0;
  v_candidate timestamptz;
  v_charge jsonb;
  v_candidate_total numeric;
BEGIN
  IF p_transportation_event_id IS NULL OR p_effective_at IS NULL OR p_total_paid IS NULL
     OR p_total_paid < 0 OR p_total_paid::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'Valid Rental payment progress inputs are required' USING ERRCODE='22023';
  END IF;

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

  v_billing_start:=coalesce(v_agreement.pricing_started_at,v_reservation.start_date);
  v_preview:=public.get_billing_preview_state(p_transportation_event_id,p_effective_at);
  IF v_preview->>'status' IS DISTINCT FROM 'billing_preview_ready' THEN
    RAISE EXCEPTION 'Authoritative Rental Billing preview is unavailable' USING ERRCODE='P0001';
  END IF;
  v_current_total:=(v_preview->>'accumulated_total')::numeric;
  v_balance_due:=greatest(v_current_total-p_total_paid,0);
  v_credit_balance:=greatest(p_total_paid-v_current_total,0);
  v_total_days:=coalesce(public.rental_pricing_days(v_billing_start,p_effective_at),0);

  IF p_total_paid >= v_current_total THEN
    v_paid_through:=p_effective_at;
    v_paid_days:=v_total_days;
    v_owed_days:=0;
    v_charge_at_paid_through:=v_current_total;
    v_partial_credit:=0;
  ELSE
    FOR v_candidate IN
      SELECT DISTINCT q.candidate
      FROM (
        SELECT b.end_time AS candidate
        FROM public.billing_lines b
        WHERE b.transportation_event_id=p_transportation_event_id
          AND b.reservation_id=v_reservation.id
          AND b.parent_billing_line_id IS NULL
          AND b.line_type IN ('initial_assignment','rental_extension')
          AND NOT b.is_open
          AND b.end_time IS NOT NULL
          AND b.end_time > v_billing_start
          AND b.end_time <= p_effective_at
        UNION ALL
        SELECT least(b.start_time+make_interval(days=>g.n),p_effective_at) AS candidate
        FROM public.billing_lines b
        CROSS JOIN LATERAL generate_series(1,greatest(coalesce(public.rental_pricing_days(b.start_time,p_effective_at),0),1)) AS g(n)
        WHERE b.transportation_event_id=p_transportation_event_id
          AND b.reservation_id=v_reservation.id
          AND b.parent_billing_line_id IS NULL
          AND b.line_type IN ('initial_assignment','rental_extension')
          AND b.start_time IS NOT NULL
          AND b.start_time < p_effective_at
        UNION ALL
        SELECT p_effective_at
      ) q
      WHERE q.candidate > v_billing_start AND q.candidate <= p_effective_at
      ORDER BY q.candidate
    LOOP
      v_charge:=public.rental_charge_through_state(p_transportation_event_id,v_candidate);
      v_candidate_total:=(v_charge->>'total')::numeric;
      IF v_candidate_total <= p_total_paid AND (v_paid_through IS NULL OR v_candidate > v_paid_through) THEN
        v_paid_through:=v_candidate;
        v_charge_at_paid_through:=v_candidate_total;
      END IF;
    END LOOP;

    IF v_paid_through IS NOT NULL THEN
      v_paid_days:=least(v_total_days,coalesce(public.rental_pricing_days(v_billing_start,v_paid_through),0));
    END IF;
    v_owed_days:=greatest(v_total_days-v_paid_days,0);
    v_partial_credit:=greatest(p_total_paid-v_charge_at_paid_through,0);
  END IF;

  RETURN jsonb_build_object(
    'status','rental_payment_progress_ready',
    'effective_at',p_effective_at,
    'current_total',v_current_total::text,
    'paid_total',p_total_paid::text,
    'paid_through_at',v_paid_through,
    'paid_charge_days',v_paid_days,
    'owed_charge_days',v_owed_days,
    'balance_due',v_balance_due::text,
    'credit_balance',v_credit_balance::text,
    'partial_credit',v_partial_credit::text,
    'charge_through_paid_point',v_charge_at_paid_through::text
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
  v_before jsonb;
  v_after jsonb;
  v_balance numeric;
BEGIN
  SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.v_user_effective_permissions WHERE user_id=v_user AND permission_key='billing.case_start') THEN RAISE EXCEPTION 'Billing payment permission is required' USING ERRCODE='42501'; END IF;
  IF p_payment_amount IS NULL OR p_payment_amount<=0 OR p_payment_amount::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero' USING ERRCODE='22023';
  END IF;

  v_existing_paid:=public.rental_recorded_payment_total_state(p_transportation_event_id);
  v_before:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid,v_effective_at);
  v_balance:=(v_before->>'balance_due')::numeric;
  IF p_payment_amount>v_balance THEN
    RAISE EXCEPTION 'Payment amount exceeds the current Rental balance' USING ERRCODE='22023';
  END IF;
  v_after:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid+p_payment_amount,v_effective_at);

  RETURN jsonb_build_object(
    'status','rental_payment_amount_preview_ready',
    'effective_at',v_effective_at,
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
  v_before jsonb;
  v_after jsonb;
  v_target jsonb;
  v_target_total numeric;
  v_current_total numeric;
  v_required numeric;
BEGIN
  SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.v_user_effective_permissions WHERE user_id=v_user AND permission_key='billing.case_start') THEN RAISE EXCEPTION 'Billing payment permission is required' USING ERRCODE='42501'; END IF;
  IF p_paid_through_at IS NULL OR p_paid_through_at>v_effective_at THEN
    RAISE EXCEPTION 'Paid Through must be a current or past date/time' USING ERRCODE='22023';
  END IF;

  v_existing_paid:=public.rental_recorded_payment_total_state(p_transportation_event_id);
  v_before:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid,v_effective_at);
  v_current_total:=(v_before->>'current_total')::numeric;
  v_target:=public.rental_charge_through_state(p_transportation_event_id,p_paid_through_at);
  v_target_total:=(v_target->>'total')::numeric;
  v_required:=greatest(least(v_target_total,v_current_total)-v_existing_paid,0);
  v_after:=public.rental_payment_progress_state(p_transportation_event_id,v_existing_paid+v_required,v_effective_at);

  RETURN jsonb_build_object(
    'status','rental_payment_through_preview_ready',
    'effective_at',v_effective_at,
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
  SELECT min(ve.actual_out_at) INTO v_actual_out FROM public.vehicle_events ve WHERE ve.transportation_event_id=p_transportation_event_id AND ve.actual_out_at IS NOT NULL;

  v_total_paid:=public.rental_recorded_payment_total_state(p_transportation_event_id);
  v_progress:=public.rental_payment_progress_state(p_transportation_event_id,v_total_paid,v_effective_at);

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
    'paid_total',v_progress->>'paid_total',
    'balance_due',v_progress->>'balance_due',
    'current_balance_paid_in_full',(v_progress->>'balance_due')::numeric=0,
    'total_charge_days',coalesce(public.rental_pricing_days(v_billing_start,v_effective_at),0),
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

CREATE OR REPLACE FUNCTION public.record_rental_payment_entry_state(
  p_transportation_event_id uuid,
  p_payment_amount numeric,
  p_reference_type text DEFAULT NULL,
  p_reference_number text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid;
  v_reservation public.reservations%rowtype;
  v_event public.transportation_events%rowtype;
  v_reference_type text;
  v_reference_number text;
  v_preview jsonb;
  v_entry_id uuid;
BEGIN
  SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.v_user_effective_permissions WHERE user_id=v_user AND permission_key='billing.case_start') THEN
    RAISE EXCEPTION 'Billing payment permission is required' USING ERRCODE='42501';
  END IF;

  SELECT r.* INTO v_reservation
  FROM public.reservations r
  WHERE r.transportation_event_id=p_transportation_event_id AND lower(btrim(coalesce(r.reservation_type,'')))='rental'
  ORDER BY r.created_at,r.id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rental reservation was not found' USING ERRCODE='P0002'; END IF;
  SELECT te.* INTO v_event FROM public.transportation_events te WHERE te.id=p_transportation_event_id FOR UPDATE;
  IF NOT FOUND OR lower(btrim(coalesce(v_event.status,'')))<>'active' OR v_reservation.actual_return_datetime IS NOT NULL THEN
    RAISE EXCEPTION 'Rental payment can only be recorded on an active Rental' USING ERRCODE='P0001';
  END IF;

  v_reference_number:=nullif(btrim(p_reference_number),'');
  IF v_reference_number IS NULL THEN v_reference_type:=NULL;
  ELSE
    v_reference_type:=upper(btrim(coalesce(p_reference_type,'')));
    IF v_reference_type NOT IN ('SO','RO') THEN RAISE EXCEPTION 'Payment reference type must be SO or RO' USING ERRCODE='22023'; END IF;
  END IF;

  v_preview:=public.preview_rental_payment_amount_state(p_transportation_event_id,p_payment_amount);

  INSERT INTO public.rental_payment_entries(
    transportation_event_id,reservation_id,amount,payment_at,reference_type,reference_number,recorded_by_user_id,
    paid_through_after,paid_days_after,remaining_days_after,remaining_amount_after,partial_credit_after
  ) VALUES (
    p_transportation_event_id,v_reservation.id,p_payment_amount,clock_timestamp(),v_reference_type,v_reference_number,v_user,
    (v_preview->>'paid_through_after')::timestamptz,(v_preview->>'paid_days_after')::integer,(v_preview->>'remaining_days_after')::integer,
    (v_preview->>'remaining_amount_after')::numeric,(v_preview->>'partial_credit_after')::numeric
  ) RETURNING id INTO v_entry_id;

  INSERT INTO public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata)
  VALUES ('rental_payment_entry',v_entry_id::text,'rental_payment_recorded','amount',NULL,p_payment_amount::text,v_user::text,
    jsonb_build_object('transportation_event_id',p_transportation_event_id,'reservation_id',v_reservation.id,'reference_present',v_reference_number IS NOT NULL,'reference_type',v_reference_type,'paid_through_after',v_preview->'paid_through_after','remaining_amount_after',v_preview->>'remaining_amount_after'));

  RETURN public.get_rental_payment_staff_state(p_transportation_event_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.set_rental_payment_reference_state(
  p_payment_source text,
  p_payment_id uuid,
  p_reference_type text,
  p_reference_number text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid;
  v_type text;
  v_number text;
  v_event_id uuid;
  v_old_type text;
  v_old_number text;
BEGIN
  SELECT id INTO v_user FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active application user required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.v_user_effective_permissions WHERE user_id=v_user AND permission_key='billing.case_start') THEN
    RAISE EXCEPTION 'Billing payment permission is required' USING ERRCODE='42501';
  END IF;

  v_number:=nullif(btrim(p_reference_number),'');
  v_type:=upper(btrim(coalesce(p_reference_type,'')));
  IF v_number IS NULL OR v_type NOT IN ('SO','RO') THEN RAISE EXCEPTION 'A valid SO or RO reference is required' USING ERRCODE='22023'; END IF;

  IF p_payment_source='payment_entry' THEN
    SELECT transportation_event_id,reference_type,reference_number INTO v_event_id,v_old_type,v_old_number
    FROM public.rental_payment_entries WHERE id=p_payment_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Rental payment entry was not found' USING ERRCODE='P0002'; END IF;
    UPDATE public.rental_payment_entries SET reference_type=v_type,reference_number=v_number WHERE id=p_payment_id;
  ELSIF p_payment_source='legacy_billing_line' THEN
    SELECT transportation_event_id,rental_payment_reference_type,rental_payment_reference_number INTO v_event_id,v_old_type,v_old_number
    FROM public.billing_lines WHERE id=p_payment_id AND rental_paid_in_full FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Legacy Rental payment was not found' USING ERRCODE='P0002'; END IF;
    UPDATE public.billing_lines SET rental_payment_reference_type=v_type,rental_payment_reference_number=v_number,updated_at=clock_timestamp() WHERE id=p_payment_id;
  ELSE
    RAISE EXCEPTION 'Unsupported Rental payment source' USING ERRCODE='22023';
  END IF;

  INSERT INTO public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata)
  VALUES ('rental_payment',p_payment_id::text,'rental_payment_reference_recorded','rental_payment_reference',concat_ws(' ',v_old_type,v_old_number),concat_ws(' ',v_type,v_number),v_user::text,jsonb_build_object('transportation_event_id',v_event_id,'payment_source',p_payment_source));

  RETURN public.get_rental_payment_staff_state(v_event_id);
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
  v_current_total numeric;
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
    v_current_total:=(public.rental_charge_through_state(v_row.event_id,clock_timestamp())->>'total')::numeric;
    v_paid:=public.rental_recorded_payment_total_state(v_row.event_id);
    IF v_current_total>v_paid THEN
      item_type:='unpaid_rental';source_id:=v_row.event_id;reservation_id:=v_row.reservation_id;vehicle_id:=v_row.vehicle_id;
      risk_level:=NULL;source_status:=v_row.status;expected_return_snapshot:=v_row.expected_return_at;contract_period_id:=NULL;reminder_state:=NULL;
      message:='Rental has an unpaid balance. Balance Due: $'||(v_current_total-v_paid)::text;
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
 SELECT * FROM public.rental_payment_warning_rows();

ALTER FUNCTION public.rental_recorded_payment_total_state(uuid) OWNER TO postgres;
ALTER FUNCTION public.rental_charge_through_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.rental_payment_progress_state(uuid,numeric,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) OWNER TO postgres;
ALTER FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_rental_payment_staff_state(uuid) OWNER TO postgres;
ALTER FUNCTION public.record_rental_payment_entry_state(uuid,numeric,text,text) OWNER TO postgres;
ALTER FUNCTION public.set_rental_payment_reference_state(text,uuid,text,text) OWNER TO postgres;
ALTER FUNCTION public.rental_payment_warning_rows() OWNER TO postgres;

REVOKE ALL ON FUNCTION public.rental_recorded_payment_total_state(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.rental_charge_through_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.rental_payment_progress_state(uuid,numeric,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.get_rental_payment_staff_state(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_rental_payment_staff_state(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.record_rental_payment_entry_state(uuid,numeric,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_rental_payment_entry_state(uuid,numeric,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.set_rental_payment_reference_state(text,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_rental_payment_reference_state(text,uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.rental_payment_warning_rows() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rental_payment_warning_rows() TO authenticated;

COMMENT ON TABLE public.rental_payment_entries IS 'Internal Rental payment ledger. Payment amount is total customer money including tax; browser staff mutate only through audited RPCs.';
COMMENT ON FUNCTION public.preview_rental_payment_amount_state(uuid,numeric) IS 'Previews a Rental payment amount and returns authoritative Paid Through, paid/owed days, partial credit, and remaining balance.';
COMMENT ON FUNCTION public.preview_rental_payment_through_state(uuid,timestamptz) IS 'Previews the exact payment needed to reach a requested Paid Through point using authoritative Rental block pricing.';
COMMENT ON FUNCTION public.record_rental_payment_entry_state(uuid,numeric,text,text) IS 'Records one audited Rental payment without changing Reservation timing or creating an Extension. SO/RO proof is optional at payment time.';
