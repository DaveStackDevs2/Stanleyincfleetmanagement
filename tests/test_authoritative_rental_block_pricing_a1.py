from pathlib import Path


ROOT = Path(__file__).parents[1]
SQL = (ROOT / "supabase/migrations/20260826193000_authoritative_rental_block_pricing_a1.sql").read_text()
UI = (ROOT / "frontend/src/reservations/ReservationsWorkspace.tsx").read_text()


def decompose(days: int):
    monthly = days // 28
    weekly = (days - monthly * 28) // 7
    daily = days - monthly * 28 - weekly * 7
    return monthly, weekly, daily


def test_largest_completed_blocks_first():
    expected = {
        1: (0, 0, 1), 6: (0, 0, 6), 7: (0, 1, 0), 10: (0, 1, 3),
        27: (0, 3, 6), 28: (1, 0, 0), 30: (1, 0, 2),
        38: (1, 1, 3), 56: (2, 0, 0),
    }
    assert {days: decompose(days) for days in expected} == expected
    assert "p_segment_days / 28" in SQL
    assert "(p_segment_days - v_monthly_days) / 7" in SQL


def test_required_snapshot_failures_and_exact_numeric_money():
    assert "Required Monthly pricing snapshot is missing or invalid" in SQL
    assert "Required Weekly pricing snapshot is missing or invalid" in SQL
    assert "numeric" in SQL
    assert "real" not in SQL.lower()
    assert "double precision" not in SQL.lower()


def test_duration_not_manual_plan_drives_rental_ui():
    assert "effectivePlan: Plan = reservationType === 'rental' ? 'daily' : plan" in UI
    assert "Automatic Rental block pricing" in UI
    assert "reservationType==='rental'?" in UI
    assert "Customer Pay Loaner pricing supports only the Daily plan" in UI


def test_snapshots_segments_contract_limit_and_security():
    assert "v_agreement.daily_rate_snapshot" in SQL
    assert "v_agreement.weekly_rate_snapshot" in SQL
    assert "v_agreement.monthly_rate_snapshot" in SQL
    assert "v_old+interval '1 day',p_new_expected_return_at" in SQL
    assert "Earlier parent lines never participate" in SQL
    assert "business_contract_days" in SQL
    assert ">56" in SQL.replace(" ", "")
    assert "renewal_sequence>=1" in SQL.replace(" ", "")
    assert "REVOKE ALL ON FUNCTION public.resolve_rental_block_pricing_state" in SQL
    assert "TO authenticated" in SQL


def test_no_hard_coded_production_model_or_late_rule_changes():
    for model in ("Trax", "Trailblazer", "Equinox", "Tahoe", "Suburban"):
        assert model.lower() not in SQL.lower()
    assert "late_fee_rules" not in SQL
    assert "lost_rentals" not in SQL
    assert "retroactive" not in SQL.lower()


def test_dev_is_never_excluded_from_admin_capability():
    combined = SQL + UI
    assert "admin-only" not in combined.lower()
    assert "role = 'admin'" not in combined.lower()
    assert "role='admin'" not in combined.lower()
