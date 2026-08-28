from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260827193000_rental_payment_progress_ledger.sql"
WORKSPACE = ROOT / "frontend/src/billing/BillingWorkspace.tsx"
CSS = ROOT / "frontend/src/billing/RentalBillingWorkspace.css"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_case_level_rental_payment_ledger_is_private_and_audited():
    sql = text(MIGRATION).lower()
    assert "create table public.rental_payment_entries" in sql
    assert "alter table public.rental_payment_entries enable row level security" in sql
    assert "revoke all on table public.rental_payment_entries from public, anon, authenticated" in sql
    assert "record_rental_payment_entry_state" in sql
    assert "rental_payment_recorded" in sql
    assert "billing.case_start" in sql
    assert "aal2 required" in sql


def test_both_payment_drivers_use_authoritative_backend_math():
    sql = text(MIGRATION)
    tsx = text(WORKSPACE)
    assert "preview_rental_payment_amount_state" in sql
    assert "preview_rental_payment_through_state" in sql
    assert "rental_charge_through_state" in sql
    assert "resolve_rental_block_pricing_state" in sql
    assert "preview_rental_payment_amount_state" in tsx
    assert "preview_rental_payment_through_state" in tsx
    assert "Enter Amount" in tsx
    assert "Choose Paid Through" in tsx
    assert "partial_credit_after" in sql
    assert "Days Still Due" in tsx


def test_overdue_is_current_billing_period_not_extension():
    tsx = text(WORKSPACE)
    assert "Current Billing Period" in tsx
    assert "Current Extension" not in tsx
    assert "OVERDUE — NOT EXTENDED" in tsx
    assert "No automatic Extension has been created" in tsx


def test_payments_are_case_level_and_periods_are_history_only():
    tsx = text(WORKSPACE)
    assert "RentalPeriodRow" in tsx
    assert "RentalPaymentControl" in tsx
    assert "Payment History" in tsx
    assert "record_rental_payment_entry_state" in tsx
    assert "record_rental_billing_line_payment_state" not in tsx
    assert "NO CHARGE" in tsx


def test_each_payment_can_carry_optional_so_or_ro_and_warning_persists_until_fixed():
    sql = text(MIGRATION)
    tsx = text(WORKSPACE)
    assert "reference_type" in sql and "reference_number" in sql
    assert "rental_payment_reference_missing" in sql
    assert "set_rental_payment_reference_state" in sql
    assert "set_rental_payment_reference_state" in tsx
    assert "Reference missing · Warning Center" in tsx
    assert "WITH (security_invoker = true)" in sql


def test_frontend_does_not_calculate_rental_money():
    tsx = text(WORKSPACE).lower()
    assert "resolve_rental_block_pricing_state" not in tsx
    assert "rental_charge_through_state" not in tsx
    assert ".from('rental_payment_entries')" not in tsx
    assert '.from("rental_payment_entries")' not in tsx
    assert "payment-preview-grid" in text(CSS)


def test_payment_target_uses_scheduled_return_when_future_and_now_when_overdue():
    sql = text(MIGRATION) + (ROOT / "supabase/migrations/20260827194500_rental_payment_scheduled_target.sql").read_text(encoding="utf-8")
    tsx = text(WORKSPACE)
    assert "rental_payment_target_state" in sql
    assert "v_event.expected_return_at" in sql
    assert "payment_target_at" in sql
    assert "payment_target_total" in sql
    assert "p_paid_through_at>v_payment_target_at" in sql
    assert "scheduled Rental return/payment target" in sql
    assert "payment_target_at" in tsx
    assert "paymentTargetInput" in tsx
    assert "Paid Through<input type=\"datetime-local\" value={through} max={paymentTargetInput}" in tsx
    assert "scheduled/current Rental payment target" in tsx
