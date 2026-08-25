from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/20260825180000_rental_capacity_admin_impact_warnings.sql').read_text()
ADMIN=(ROOT/'frontend/src/admin/ReservationCapacityManagement.tsx').read_text()

def test_authoritative_evaluator_uses_future_new_york_half_open_days():
    assert "evaluate_admin_rental_reservation_capacity_impact" in SQL
    assert "America/New_York" in SQL and "interval '1 microsecond'" in SQL
    assert "greatest((r.start_date" in SQL and "v_today" in SQL
    assert "r.start_date<((cd.local_date+1)" in SQL
    assert "r.expected_return_datetime>(cd.local_date" in SQL

def test_reservation_commitment_filters_and_details_are_authoritative():
    for clause in ("reservation_type,'')))='rental'","te.status='active'","a.is_active=true","a.pricing_started_at is null","status,''))<>'cancelled'"):
        assert clause in SQL
    for field in ("'reservation_id'","'customer_id'","'customer_name'","'conflict_dates'","'reservation_overage'"):
        assert field in SQL
    assert "reservation_count>v_effective_limit" in SQL

def test_quotes_are_separate_nonbinding_pressure_and_exclude_inactive_records():
    assert "reservation_count+quote_count>v_effective_limit" in SQL
    assert "q.is_active=true" in SQL and "q.converted_to_reservation_id is null" in SQL
    assert "lower(coalesce(q.status,''))='active'" in SQL
    assert "a.origin_type='quote'" in SQL and "a.reservation_id is null and a.is_active=true" in SQL
    for field in ("'quote_id'","'risk_dates'","'active_quote_count'","'at_risk_quote_pressure'"):
        assert field in SQL

def test_admin_union_keeps_future_referenced_models_until_impact_is_resolved():
    get_admin=SQL.split("create or replace function public.get_admin_rental",1)[1].split("create or replace function public.upsert_admin",1)[0]
    assert "referenced_models as" in get_admin and "canonical_models as" in get_admin
    for eligibility in ("te.status='active'","a.pricing_started_at is null","status,''))<>'cancelled'","q.is_active=true","q.converted_to_reservation_id is null"):
        assert eligibility in get_admin
    assert "union all select vehicle_class,2 from referenced_models" in get_admin
    assert "left join public.rental_model_limits" in get_admin and "left join active_rates" in get_admin
    assert "'has_active_rate_card'" in get_admin and "'configured'" in get_admin
    assert "evaluate_admin_rental_reservation_capacity_impact(vehicle_class,daily_limit)" in get_admin

def test_save_and_remove_accept_normalized_models_and_return_immediate_impact():
    upsert=SQL.split("create or replace function public.upsert_admin",1)[1].split("create or replace function public.remove_admin",1)[0]
    remove=SQL.split("create or replace function public.remove_admin",1)[1].split("alter function public.evaluate",1)[0]
    assert "Active Rental rate card not found" not in upsert+remove
    assert "select vehicle_class into v_class from public.rental_model_limits" in upsert
    assert "lower(btrim(vehicle_class))=lower" in upsert+remove
    assert "pg_catalog.pg_advisory_xact_lock" in upsert and "pg_catalog.pg_advisory_xact_lock" in remove
    assert "evaluate_admin_rental_reservation_capacity_impact(v_class,p_daily_limit)" in upsert
    assert "evaluate_admin_rental_reservation_capacity_impact(v_class,null)" in remove
    assert "p_daily_limit<0" in upsert  # zero remains valid

def test_security_and_execute_boundaries_are_preserved():
    assert SQL.count("permission_key='user_admin.manage'")==3
    assert SQL.count("coalesce(auth.jwt()->>'aal','')<>'aal2'")==3
    assert SQL.lower().count("security definer set search_path to ''")==4
    assert "revoke all on function public.evaluate_admin_rental_reservation_capacity_impact(text,integer) from public,anon,authenticated" in SQL
    assert "to service_role" in SQL

def test_frontend_renders_backend_impact_without_capacity_arithmetic():
    assert "Add Model Capacity" in ADMIN
    assert "has_active_rate_card" in ADMIN
    assert "hard_reservation_conflicts" in ADMIN and "at_risk_quotes" in ADMIN
    assert "Hard Reservation conflicts" in ADMIN and "At-risk Quote pressure" in ADMIN
    assert "Quotes are non-binding" in ADMIN
    for field in ("item?.days","capacity_configured","reservation_count","reservation_overage","active_quote_count","combined_count","quote_pressure_overage"):
        assert field in ADMIN
    assert "Saved/effective capacity" in ADMIN and "Unavailable (effective capacity:" in ADMIN
    assert "Hard Reservation overage" in ADMIN and "Quote-pressure overage" in ADMIN
    assert "reservationCount+" not in ADMIN and "activeQuoteCount+" not in ADMIN
    assert "from('rental_model_limits')" not in ADMIN
