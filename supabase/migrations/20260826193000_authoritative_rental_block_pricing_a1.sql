-- Checkpoint A1: authoritative, segment-scoped Rental pricing. Data-free.
-- Weekly/monthly snapshots are per-day rates; no vehicle-model price is code.

ALTER TABLE public.billing_lines
  ADD COLUMN IF NOT EXISTS rental_block_pricing_snapshot jsonb;

-- Rental pricing uses completed elapsed days.  Keep this boundary separate from
-- business_contract_days(), whose inclusive semantics remain authoritative for
-- Loaner, EW, and legacy Billing workflows.
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
    ELSE greatest(public.business_contract_days(p_segment_start,p_segment_end)-1,0)
  END
$function$;

CREATE OR REPLACE FUNCTION public.resolve_rental_block_pricing_state(
  p_segment_days integer,
  p_daily_rate numeric,
  p_weekly_rate numeric,
  p_monthly_rate numeric
) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_monthly_blocks integer; v_weekly_blocks integer; v_daily_days integer;
  v_monthly_days integer; v_weekly_days integer;
  v_monthly_amount numeric; v_weekly_amount numeric; v_daily_amount numeric;
BEGIN
  IF p_segment_days IS NULL OR p_segment_days < 0 THEN
    RAISE EXCEPTION 'Rental segment days must be a nonnegative whole number' USING ERRCODE='22023';
  END IF;
  IF p_daily_rate IS NULL OR p_daily_rate < 0 OR p_daily_rate::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'Required Daily pricing snapshot is missing or invalid' USING ERRCODE='22023';
  END IF;
  v_monthly_blocks := p_segment_days / 28;
  v_monthly_days := v_monthly_blocks * 28;
  v_weekly_blocks := (p_segment_days - v_monthly_days) / 7;
  v_weekly_days := v_weekly_blocks * 7;
  v_daily_days := p_segment_days - v_monthly_days - v_weekly_days;
  IF v_monthly_blocks > 0 AND (p_monthly_rate IS NULL OR p_monthly_rate < 0 OR p_monthly_rate::text IN ('NaN','Infinity','-Infinity')) THEN
    RAISE EXCEPTION 'Required Monthly pricing snapshot is missing or invalid' USING ERRCODE='22023';
  END IF;
  IF v_weekly_blocks > 0 AND (p_weekly_rate IS NULL OR p_weekly_rate < 0 OR p_weekly_rate::text IN ('NaN','Infinity','-Infinity')) THEN
    RAISE EXCEPTION 'Required Weekly pricing snapshot is missing or invalid' USING ERRCODE='22023';
  END IF;
  v_monthly_amount := v_monthly_days * coalesce(p_monthly_rate,0);
  v_weekly_amount := v_weekly_days * coalesce(p_weekly_rate,0);
  v_daily_amount := v_daily_days * p_daily_rate;
  RETURN jsonb_build_object(
    'status','rental_block_pricing_resolved','segment_days',p_segment_days,
    'monthly',jsonb_build_object('blocks',v_monthly_blocks,'days',v_monthly_days,'per_day_rate',p_monthly_rate::text,'amount',v_monthly_amount::text),
    'weekly',jsonb_build_object('blocks',v_weekly_blocks,'days',v_weekly_days,'per_day_rate',p_weekly_rate::text,'amount',v_weekly_amount::text),
    'daily',jsonb_build_object('days',v_daily_days,'per_day_rate',p_daily_rate::text,'amount',v_daily_amount::text),
    'subtotal',(v_monthly_amount+v_weekly_amount+v_daily_amount)::text);
END;
$function$;

CREATE OR REPLACE FUNCTION public.preview_rental_agreement_segment_state(
  p_pricing_agreement_id uuid, p_segment_start timestamptz, p_segment_end timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_actor uuid; v_agreement public.rental_pricing_agreements%rowtype; v_pay_type text; v_days integer; v_price jsonb; v_tax jsonb;
BEGIN
  SELECT id INTO v_actor FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501'; END IF;
  IF coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN RAISE EXCEPTION 'AAL2 authentication is required' USING ERRCODE='42501'; END IF;
  IF p_segment_start IS NULL OR p_segment_end IS NULL OR p_segment_end <= p_segment_start THEN RAISE EXCEPTION 'A valid Rental segment period is required' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_agreement FROM public.rental_pricing_agreements WHERE id=p_pricing_agreement_id AND is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active pricing agreement was not found' USING ERRCODE='P0002'; END IF;
  v_days:=public.rental_pricing_days(p_segment_start,p_segment_end);
  IF v_days > 56 THEN RAISE EXCEPTION 'Same-vehicle intended Rental period cannot exceed 56 contract days' USING ERRCODE='22023'; END IF;
  v_price:=public.resolve_rental_block_pricing_state(v_days,v_agreement.daily_rate_snapshot,v_agreement.weekly_rate_snapshot,v_agreement.monthly_rate_snapshot);
  SELECT pay_type INTO v_pay_type FROM public.pay_type_rules WHERE id=v_agreement.pay_type_rule_id;
  IF v_pay_type IS NULL THEN RAISE EXCEPTION 'Pricing-agreement pay type was not found' USING ERRCODE='P0002'; END IF;
  v_tax:=public.resolve_billing_tax_state(v_pay_type,(v_price->>'subtotal')::numeric);
  RETURN v_price || jsonb_build_object('status','rental_segment_preview_ready','pricing_agreement_id',v_agreement.id,'segment_start',p_segment_start,'segment_end',p_segment_end,'tax_amount',v_tax->>'tax_amount','total',((v_price->>'subtotal')::numeric+(v_tax->>'tax_amount')::numeric)::text,'tax',v_tax);
END;$function$;

CREATE OR REPLACE FUNCTION public.get_rental_contract_status_state(p_reservation_id uuid, p_effective_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_actor uuid; v_r public.reservations%rowtype; v_cp public.contract_periods%rowtype; v_days integer; v_due timestamptz; v_state text;
BEGIN
 SELECT id INTO v_actor FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
 IF v_actor IS NULL THEN RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_r FROM public.reservations WHERE id=p_reservation_id;
 IF NOT FOUND OR lower(coalesce(v_r.reservation_type,'')) NOT LIKE '%rental%' THEN RAISE EXCEPTION 'Rental reservation was not found' USING ERRCODE='P0002'; END IF;
 IF public.rental_pricing_days(v_r.start_date,v_r.expected_return_datetime)>56 THEN RAISE EXCEPTION 'Same-vehicle intended Rental period cannot exceed 56 contract days' USING ERRCODE='22023'; END IF;
 SELECT cp.* INTO v_cp FROM public.contract_periods cp JOIN public.vehicle_events ve ON ve.id=cp.vehicle_event_id WHERE ve.transportation_event_id=v_r.transportation_event_id AND cp.is_open ORDER BY cp.renewal_sequence DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','rental_contract_status_unavailable','reservation_id',p_reservation_id); END IF;
 v_days:=public.business_contract_days(v_cp.contract_out_at,p_effective_at); v_due:=v_cp.contract_out_at+interval '28 days';
 v_state:=CASE WHEN v_cp.renewal_sequence>=1 AND p_effective_at>=v_due THEN 'swap_required' WHEN v_cp.renewal_sequence>=1 THEN 'second_contract_active' WHEN p_effective_at>=v_due THEN 'renewal_required' ELSE 'first_contract_active' END;
 RETURN jsonb_build_object('status','rental_contract_status_ready','reservation_id',p_reservation_id,'contract_period_id',v_cp.id,'renewal_sequence',v_cp.renewal_sequence,'contract_state',v_state,'action_due_at',v_due,'automatic_action',false);
END;$function$;

-- Extension money is the new interval only. Earlier parent lines never participate.
CREATE OR REPLACE FUNCTION public.preview_rental_extension_state(p_reservation_id uuid,p_new_expected_return_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_actor uuid; v_r public.reservations%rowtype; v_a public.rental_pricing_agreements%rowtype; v_line public.billing_lines%rowtype; v_old timestamptz; v_price jsonb;
BEGIN
 SELECT id INTO v_actor FROM public.app_users WHERE auth_user_id=auth.uid() AND is_active=true;
 IF v_actor IS NULL THEN RAISE EXCEPTION 'An active application user is required' USING ERRCODE='42501'; END IF;
 IF coalesce(auth.jwt()->>'aal','')<>'aal2' THEN RAISE EXCEPTION 'AAL2 authentication is required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_r FROM public.reservations WHERE id=p_reservation_id;
 SELECT * INTO v_a FROM public.rental_pricing_agreements WHERE reservation_id=p_reservation_id AND is_active=true;
 SELECT coalesce(te.expected_return_at,v_r.expected_return_datetime) INTO v_old FROM public.transportation_events te WHERE te.id=v_r.transportation_event_id;
 SELECT * INTO v_line FROM public.billing_lines WHERE reservation_id=p_reservation_id AND parent_billing_line_id IS NULL AND line_type IN ('initial_assignment','rental_extension') AND is_open ORDER BY start_time DESC,id DESC LIMIT 1;
 IF v_r.id IS NULL OR v_a.id IS NULL OR v_line.id IS NULL THEN RAISE EXCEPTION 'Rental Extension pricing state is unavailable' USING ERRCODE='P0002'; END IF;
 IF p_new_expected_return_at IS NULL OR p_new_expected_return_at<=v_old THEN RAISE EXCEPTION 'New return must be later than current return' USING ERRCODE='22023'; END IF;
 IF public.rental_pricing_days(v_r.start_date,p_new_expected_return_at)>56 THEN RAISE EXCEPTION 'Same-vehicle intended Rental period cannot exceed 56 contract days' USING ERRCODE='22023'; END IF;
 -- The elapsed interval owns the shared boundary once, so prior segments stay isolated.
 v_price:=public.preview_rental_agreement_segment_state(v_a.id,v_old,p_new_expected_return_at);
 RETURN jsonb_build_object('status','rental_extension_preview_ready','reservation_id',p_reservation_id,'transportation_event_id',v_r.transportation_event_id,'current_parent_billing_line_id',v_line.id,'previous_expected_return_at',v_old,'proposed_expected_return_at',p_new_expected_return_at,'additional_charge',v_price->>'subtotal','additional_tax',v_price->>'tax_amount','additional_total',v_price->>'total','block_pricing',v_price);
END;$function$;

ALTER FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) OWNER TO postgres;
ALTER FUNCTION public.rental_pricing_days(timestamptz,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.preview_rental_agreement_segment_state(uuid,timestamptz,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.get_rental_contract_status_state(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.preview_rental_extension_state(uuid,timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.rental_pricing_days(timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.preview_rental_agreement_segment_state(uuid,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_rental_contract_status_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.preview_rental_extension_state(uuid,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.preview_rental_agreement_segment_state(uuid,timestamptz,timestamptz),public.get_rental_contract_status_state(uuid,timestamptz),public.preview_rental_extension_state(uuid,timestamptz) TO authenticated;

-- Internal resolver is callable only by trusted function owners/service operations.
GRANT EXECUTE ON FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.rental_pricing_days(timestamptz,timestamptz) TO service_role;

COMMENT ON FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) IS 'One shared exact Rental segment resolver: completed 28-day, then 7-day, then Daily blocks.';
COMMENT ON FUNCTION public.rental_pricing_days(timestamptz,timestamptz) IS 'Authoritative completed-day boundary for Rental pricing only; intentionally excludes the inclusive end boundary.';
COMMENT ON COLUMN public.billing_lines.rental_block_pricing_snapshot IS 'Immutable explanation of the authoritative segment charge persisted by Rental workflows.';
