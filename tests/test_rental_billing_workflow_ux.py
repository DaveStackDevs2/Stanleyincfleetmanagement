from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260827154000_rental_billing_workflow_ux.sql"
TIER_FALLBACK = ROOT / "supabase/migrations/20260827154500_rental_optional_discount_tier_fallback.sql"
WORKSPACE = ROOT / "frontend/src/billing/BillingWorkspace.tsx"
CSS = ROOT / "frontend/src/billing/RentalBillingWorkspace.css"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_partial_rental_days_round_up_without_changing_shared_business_days():
    sql = text(MIGRATION).lower()
    assert "create or replace function public.rental_pricing_days" in sql
    assert "ceil(extract(epoch from (p_segment_end - p_segment_start)) / 86400.0)::integer" in sql
    assert "create or replace function public.business_contract_days" not in sql


def test_unconfigured_discount_tiers_are_skipped_not_invented():
    sql = text(TIER_FALLBACK)
    lower = sql.lower()
    assert "create or replace function public.resolve_rental_block_pricing_state" in lower
    assert "if p_monthly_rate is not null then" in lower
    assert "if p_weekly_rate is not null then" in lower
    assert "v_daily_days := v_remaining" in lower
    assert "coalesce(p_monthly_rate" not in lower.split("v_monthly_blocks :=", 1)[0]
    assert "required daily pricing snapshot is missing or invalid" in lower
    assert "configured weekly pricing snapshot is invalid" in lower
    assert "configured monthly pricing snapshot is invalid" in lower


def test_payment_reference_is_optional_but_missing_proof_is_a_persistent_condition():
    sql = text(MIGRATION)
    lower = sql.lower()
    assert "record_rental_billing_line_payment_state" in sql
    assert "p_reference_type text DEFAULT NULL" in sql
    assert "p_reference_number text DEFAULT NULL" in sql
    assert "v_reference_number := nullif(btrim(p_reference_number),'')" in sql
    assert "rental_payment_reference_missing" in sql
    assert "b.rental_paid_in_full" in sql
    assert "nullif(btrim(b.rental_payment_reference_number),'') IS NULL" in sql
    missing_section = lower.split("'rental_payment_reference_missing'", 1)[1]
    assert "lower(btrim(te.status))='active'" not in missing_section


def test_payment_state_returns_customer_workflow_fields_and_block_pricing():
    sql = text(MIGRATION)
    for marker in (
        "'balance_due'",
        "'total_charge_days'",
        "'paid_charge_days'",
        "'owed_charge_days'",
        "'paid_through_at'",
        "'overdue_days'",
        "'current_block_pricing'",
        "'payment_reference_type'",
        "'payment_reference_number'",
    ):
        assert marker in sql
    assert "v_total_days := coalesce(public.rental_pricing_days(v_rental_start,v_effective_at),0)" in sql
    assert "v_paid_days := coalesce(public.rental_pricing_days(v_rental_start,v_paid_through),0)" in sql


def test_rental_ui_is_compact_and_uses_days_payment_proof_and_real_extensions():
    tsx = text(WORKSPACE)
    css = text(CSS)
    for label in ("Total Days", "Days Paid", "Paid Through", "Days Owed", "Amount Owed"):
        assert label in tsx
    for label in ("Monthly", "Weekly", "Daily"):
        assert f"['{label}'" in tsx
    assert "OVERDUE — NOT EXTENDED" in tsx
    assert "Only actual customer-approved Extensions appear here" in tsx
    assert "record_rental_payment_entry_state" in tsx
    assert "preview_rental_payment_amount_state" in tsx
    assert "preview_rental_payment_through_state" in tsx
    assert "set_rental_payment_reference_state" in tsx
    assert "record_rental_billing_line_payment_state" not in tsx
    assert "Reference missing · Warning Center" in tsx
    assert "Confirm Extension" in tsx
    assert "Extend &amp; Mark Paid in Full" not in tsx
    assert "Mark Paid in Full" not in tsx
    assert "compact-case-line" in tsx
    assert ".compact-case-line" in css
    assert ".rental-payment-row" in css


def test_warning_ui_reads_all_buckets_and_routes_to_case_state():
    tsx = text(WORKSPACE)
    assert "result.data.critical" in tsx
    assert "result.data.warning" in tsx
    assert "result.data.review_needed" in tsx
    assert "openWarning" in tsx
    assert "warningTransportationEventId" in tsx


def test_frontend_does_not_mutate_billing_tables_or_calculate_block_money():
    tsx = text(WORKSPACE).lower()
    assert ".from('billing_lines')" not in tsx
    assert '.from("billing_lines")' not in tsx
    assert "resolve_rental_block_pricing_state" not in tsx
    assert "rental_pricing_days" not in tsx
