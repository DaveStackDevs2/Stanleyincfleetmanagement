from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/20260825120000_authoritative_rental_reservation_capacity.sql').read_text()
RESERVATIONS=(ROOT/'frontend/src/reservations/ReservationsWorkspace.tsx').read_text()
FLEET=(ROOT/'frontend/src/fleet-board/FleetBoard.tsx').read_text()
ADMIN=(ROOT/'frontend/src/admin/PayTypeManagement.tsx').read_text()

def test_capacity_is_missing_or_zero_closed_and_half_open_in_maine():
    assert "when v_limit is null then 'not_configured'" in SQL
    assert "booked<v_limit" in SQL
    assert "America/New_York" in SQL
    assert "interval '1 microsecond'" in SQL
    assert "r.start_date <" in SQL and "r.expected_return_datetime >" in SQL

def test_counting_semantics_and_complete_period_alternatives():
    for clause in ["reservation_type,'')))='rental'", "te.status='active'", "a.is_active=true", "a.pricing_started_at is null", "status,''))<>'cancelled'", "bool_and(coalesce(x.booked,0)<c.daily_limit)"]:
        assert clause in SQL
    assert "rental_rate_rules" in SQL
    assert "p_exclude_reservation_id" in SQL

def test_authoritative_rental_quote_and_reservation_writes_recheck_capacity():
    assert SQL.count("Rental reservation capacity unavailable") == 4
    for function in ("create_quote", "create_reservation", "convert_quote_to_reservation", "update_precheckin_reservation"):
        assert f"{function}_with" in SQL
    assert "create_quote_with_pricing_agreement_without_capacity_state" in SQL
    assert "create_walk_in_with_pricing_agreement_state" not in SQL
    assert "pg_advisory_xact_lock" in SQL

def test_quote_capacity_is_non_holding_and_conversion_retry_is_idempotent():
    evaluator=SQL.split("create or replace function public.get_rental_reservation_capacity_state",1)[1].split("alter function public.get_rental",1)[0]
    quote=SQL.split("create function public.create_quote_with_pricing_agreement_state",1)[1].split("create function public.create_reservation",1)[0]
    conversion=SQL.split("create function public.convert_quote_to_reservation_with_pricing_agreement_state",1)[1].split("create function public.update_precheckin",1)[0]
    assert "from public.reservations r" in evaluator and "from public.quotes" not in evaluator
    assert "get_rental_reservation_capacity_state" in quote
    assert conversion.index("converted_to_reservation_id is not null") < conversion.index("get_rental_reservation_capacity_state")
    assert "for update" in conversion

def test_conversion_alternative_reuses_agreement_and_authoritative_rate_engine():
    conversion=SQL.split("create function public.convert_quote_to_reservation_with_pricing_agreement_state",1)[1].split("create function public.update_precheckin",1)[0]
    assert "p_selected_vehicle_class text default null" in conversion
    assert "resolve_rental_rate_card_state(v_conversion_class,clock_timestamp())" in conversion
    assert "current_rate_plan" in conversion and "has no configured % rate" in conversion
    assert "update public.rental_pricing_agreements set" in conversion
    for field in ("vehicle_class=v_rate->>'vehicle_class'", "rental_rate_rule_id=", "daily_rate_snapshot=", "weekly_rate_snapshot=", "monthly_rate_snapshot=", "updated_by=v_user"):
        assert field in conversion
    assert "update public.quotes set vehicle_class" not in conversion
    assert conversion.index("converted_to_reservation_id is not null") < conversion.index("resolve_rental_rate_card_state")
    assert "create_transportation_event_state" not in conversion and "insert into public.rental_pricing_agreements" not in conversion

def test_conversion_rate_plan_case_is_parenthesized_for_plpgsql():
    conversion=SQL.split("create function public.convert_quote_to_reservation_with_pricing_agreement_state",1)[1].split("create function public.update_precheckin",1)[0]
    assert """if (case v_agreement.current_rate_plan
        when 'daily' then v_rate->>'daily_rate'
        when 'weekly' then v_rate->>'weekly_rate'
        when 'monthly' then v_rate->>'monthly_rate'
        else null end) is null then""" in conversion

def test_admin_and_booking_writes_share_normalized_lock_and_upsert_identity():
    lock="pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(btrim("
    assert SQL.count(lock) >= 6
    upsert=SQL.split("create or replace function public.upsert_admin",1)[1].split("create or replace function public.remove_admin",1)[0]
    remove=SQL.split("create or replace function public.remove_admin",1)[1].split("alter function public.get_admin",1)[0]
    assert lock in upsert and lock in remove
    assert "where lower(btrim(vehicle_class))=lower(btrim(v_class))" in upsert
    assert "set vehicle_class=v_class,daily_limit=p_daily_limit" in upsert
    assert "on conflict(vehicle_class)" not in upsert

def test_admin_boundary_and_no_direct_browser_table_mutation():
    assert SQL.count("permission_key='user_admin.manage'") == 3
    assert SQL.count("coalesce(auth.jwt()->>'aal','')<>'aal2'") >= 3
    assert "security definer set search_path to ''" in SQL.lower()
    assert "from('rental_model_limits')" not in ADMIN
    assert "upsert_admin_rental_reservation_capacity_state" in ADMIN
    assert "remove_admin_rental_reservation_capacity_state" in ADMIN

def test_frontends_use_authoritative_capacity_state():
    assert "get_rental_reservation_capacity_state" in RESERVATIONS
    assert "capacity.alternatives.map" in RESERVATIONS
    assert "workflow!=='walk_in'&&(capacityLoading||!capacity?.available)" in RESERVATIONS
    assert "p_vehicle_class:vehicleModel.trim()" in RESERVATIONS
    assert "selectedRate?.[plan]" in RESERVATIONS
    assert "p_selected_vehicle_class:conversionClass||null" in RESERVATIONS
    assert "Normal current {conversion.currentPlan} rate" in RESERVATIONS
    assert "alternatives.filter(item=>item[conversion.currentPlan as Plan]!==null)" in RESERVATIONS
    assert "Checking authoritative Reservation Capacity" in RESERVATIONS
    assert "workflow==='walk_in'" in RESERVATIONS
    assert "get_fleet_board_capacity_state" in FLEET
    assert "reservations.filter(item => item.reservationType === 'rental'" not in FLEET
