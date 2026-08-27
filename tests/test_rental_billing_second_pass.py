from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260827173500_rental_billing_second_pass.sql"
WORKSPACE = ROOT / "frontend/src/billing/BillingWorkspace.tsx"
CSS = ROOT / "frontend/src/billing/RentalBillingWorkspace.css"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_billing_start_is_explicit_and_preserves_reservation_schedule():
    sql = text(MIGRATION)
    lower = sql.lower()
    assert "create or replace function public.set_rental_billing_start_state" in lower
    assert "pricing_started_at=p_billing_start_at" in lower
    assert "start_time=p_billing_start_at" in lower
    assert "rental_billing_start_adjusted" in lower
    assert "original_reserved_start" in lower
    assert "expected_return_unchanged" in lower
    assert "update public.reservations" not in lower.split("create or replace function public.set_rental_billing_start_state", 1)[1]
    assert "update public.transportation_events" not in lower.split("create or replace function public.set_rental_billing_start_state", 1)[1]


def test_staff_state_keeps_reserved_billing_and_actual_pickup_separate():
    sql = text(MIGRATION)
    for marker in (
        "'reserved_start_at'",
        "'billing_start_at'",
        "'actual_out_at'",
        "coalesce(v_agreement.pricing_started_at,v_reserved_start)",
    ):
        assert marker in sql


def test_zero_dollar_extensions_do_not_require_payment_or_keep_unpaid_warning():
    sql = text(MIGRATION).lower()
    tsx = text(WORKSPACE)
    assert "coalesce(v_row.amount,0)+coalesce(v_row.tax_amount,0)=0" in sql
    assert "and (coalesce(b.amount,0)+coalesce(b.tax_amount,0)) > 0" in sql
    assert "NO CHARGE" in tsx
    assert "No payment or SO#/RO# is required for this $0.00 period." in tsx


def test_warning_view_keeps_security_invoker():
    sql = text(MIGRATION).lower()
    assert "create or replace view public.v_warning_center_warning_items" in sql
    assert "with (security_invoker = true)" in sql


def test_rental_timeline_and_manual_controls_match_staff_workflow():
    tsx = text(WORKSPACE)
    for label in ("Reserved Start", "Billing Start", "Actual Pickup", "Expected Return"):
        assert label in tsx
    assert "get_rental_payment_staff_state" in tsx
    assert "set_rental_billing_start_state" in tsx
    assert "Use Reserved" in tsx
    assert "Use Pickup" in tsx
    assert "Use Now" in tsx
    assert "Save Billing Start" in tsx
    assert "Current Charges" in tsx
    assert "current-charge-lines" in tsx
    assert "Only actual customer-approved Extensions appear here" in tsx


def test_second_pass_ui_remains_compact_and_styled():
    css = text(CSS)
    for marker in (
        ".rental-timeline.five",
        ".billing-start-editor",
        ".current-charge-line",
        ".rental-payment-row.no-charge-row",
    ):
        assert marker in css
