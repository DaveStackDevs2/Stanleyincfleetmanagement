from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/20260825120000_authoritative_rental_reservation_capacity.sql').read_text()
RESERVATIONS=(ROOT/'frontend/src/reservations/ReservationsWorkspace.tsx').read_text()
FLEET=(ROOT/'frontend/src/fleet-board/FleetBoard.tsx').read_text()
ADMIN=(ROOT/'frontend/src/admin/ReservationCapacityManagement.tsx').read_text()

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

def test_authoritative_writes_recheck_but_quote_and_walk_in_do_not_hold_capacity():
    assert SQL.count("Rental reservation capacity unavailable") == 3
    assert "create_reservation_with_pricing_agreement_state" in SQL
    assert "convert_quote_to_reservation_with_pricing_agreement_state" in SQL
    assert "update_precheckin_reservation_state" in SQL
    assert "create_quote_with_pricing_agreement_state" not in SQL
    assert "create_walk_in_with_pricing_agreement_state" not in SQL
    assert "pg_advisory_xact_lock" in SQL

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
    assert "workflow==='walk_in'" in RESERVATIONS
    assert "get_fleet_board_capacity_state" in FLEET
    assert "reservations.filter(item => item.reservationType === 'rental'" not in FLEET
