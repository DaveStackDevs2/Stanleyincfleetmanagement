-- Preserve legacy/daily-only Rental pricing agreements when discounted tiers are not configured.
-- A missing Weekly or Monthly snapshot means that discount tier is unavailable; the resolver
-- continues with the next configured tier rather than inventing a rate or failing the case.

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
  v_remaining integer;
  v_monthly_blocks integer := 0;
  v_weekly_blocks integer := 0;
  v_daily_days integer := 0;
  v_monthly_days integer := 0;
  v_weekly_days integer := 0;
  v_monthly_amount numeric := 0;
  v_weekly_amount numeric := 0;
  v_daily_amount numeric := 0;
BEGIN
  IF p_segment_days IS NULL OR p_segment_days < 0 THEN
    RAISE EXCEPTION 'Rental segment days must be a nonnegative whole number' USING ERRCODE='22023';
  END IF;
  IF p_daily_rate IS NULL OR p_daily_rate < 0 OR p_daily_rate::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'Required Daily pricing snapshot is missing or invalid' USING ERRCODE='22023';
  END IF;
  IF p_weekly_rate IS NOT NULL AND (p_weekly_rate < 0 OR p_weekly_rate::text IN ('NaN','Infinity','-Infinity')) THEN
    RAISE EXCEPTION 'Configured Weekly pricing snapshot is invalid' USING ERRCODE='22023';
  END IF;
  IF p_monthly_rate IS NOT NULL AND (p_monthly_rate < 0 OR p_monthly_rate::text IN ('NaN','Infinity','-Infinity')) THEN
    RAISE EXCEPTION 'Configured Monthly pricing snapshot is invalid' USING ERRCODE='22023';
  END IF;

  v_remaining := p_segment_days;

  IF p_monthly_rate IS NOT NULL THEN
    v_monthly_blocks := v_remaining / 28;
    v_monthly_days := v_monthly_blocks * 28;
    v_remaining := v_remaining - v_monthly_days;
  END IF;

  IF p_weekly_rate IS NOT NULL THEN
    v_weekly_blocks := v_remaining / 7;
    v_weekly_days := v_weekly_blocks * 7;
    v_remaining := v_remaining - v_weekly_days;
  END IF;

  v_daily_days := v_remaining;
  v_monthly_amount := v_monthly_days * coalesce(p_monthly_rate,0);
  v_weekly_amount := v_weekly_days * coalesce(p_weekly_rate,0);
  v_daily_amount := v_daily_days * p_daily_rate;

  RETURN jsonb_build_object(
    'status','rental_block_pricing_resolved',
    'segment_days',p_segment_days,
    'monthly',jsonb_build_object(
      'blocks',v_monthly_blocks,
      'days',v_monthly_days,
      'per_day_rate',p_monthly_rate::text,
      'amount',v_monthly_amount::text
    ),
    'weekly',jsonb_build_object(
      'blocks',v_weekly_blocks,
      'days',v_weekly_days,
      'per_day_rate',p_weekly_rate::text,
      'amount',v_weekly_amount::text
    ),
    'daily',jsonb_build_object(
      'days',v_daily_days,
      'per_day_rate',p_daily_rate::text,
      'amount',v_daily_amount::text
    ),
    'subtotal',(v_monthly_amount+v_weekly_amount+v_daily_amount)::text
  );
END;
$function$;

ALTER FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) TO service_role;

COMMENT ON FUNCTION public.resolve_rental_block_pricing_state(integer,numeric,numeric,numeric) IS
  'Exact Rental segment resolver: use configured 28-day Monthly, then configured 7-day Weekly, then Daily; an unconfigured discount tier is skipped rather than invented.';