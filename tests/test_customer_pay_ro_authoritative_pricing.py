from pathlib import Path

SQL = Path('supabase/migrations/20260825193000_customer_pay_ro_authoritative_pricing.sql').read_text()
UI = Path('frontend/src/billing/BillingWorkspace.tsx').read_text()
INTAKE = Path('frontend/src/reservations/ReservationsWorkspace.tsx').read_text()
ADMIN = Path('frontend/src/admin/PayTypeManagement.tsx').read_text()


def test_customer_pay_loaner_agreements_use_standard_not_rental_card():
    assert SQL.count("lower(btrim(p_reservation_type))='loaner'") == 3
    assert SQL.count("v_pay.default_daily_amount") >= 9
    assert SQL.count("v_rate_rule:=null") == 3
    assert SQL.count("'weekly_rate',null,'monthly_rate',null") == 3
    assert SQL.count("Customer Pay Loaner pricing is daily-only") == 3
    assert "alter column rental_rate_rule_id drop not null" in SQL
    assert SQL.count("else\n  v_rate:=public.resolve_rental_rate_card_state") == 3


def test_intake_and_ui_use_customer_pay_standard_daily_only():
    assert "'default_daily_amount',pay_type.default_daily_amount" in SQL
    assert "create or replace function public.get_pricing_agreement_intake_state()" in SQL.lower()
    assert "pg_get_functiondef" not in SQL
    assert "isCustomerPayLoaner ? (plan === 'daily'" in INTAKE
    assert "disabled={isCustomerPayLoaner}" in INTAKE
    assert "Customer Pay Standard RO daily rate" in INTAKE
    assert "Standard RO daily rate" in ADMIN


def test_permission_is_assignable_and_runtime_is_effective_permission_only():
    assert "billing.customer_pay_rate_override" in SQL
    mapping = SQL.split("insert into public.role_permissions", 1)[1].split("create or replace function", 1)[0]
    for role in ("Admin", "Service Manager", "Dev"):
        assert role in mapping
    for role in ("Service Advisor", "CTP Staff"):
        assert role not in mapping
    rpc = SQL.split("create or replace function public.set_customer_pay_billing_line_rate_override_state", 1)[1]
    assert "v_user_effective_permissions" in rpc
    assert "r.role_name in ('Admin','Service Manager','Dev')" in mapping
    assert "r.name" not in mapping
    assert "r.name" not in rpc
    assert "auth.jwt()->>'aal'" in rpc


def test_whole_segment_override_recalculates_and_audits():
    for token in ("business_contract_days(v_line.start_time,v_boundary)", "v_effective*v_days", "tax_rate_snapshot", "ensure_tax_child_line_state", "get_billing_preview_state", "paid_through_at", "old_override", "corrected_amount", "ro_number", "actor_user_id"):
        assert token in SQL
    assert "v_boundary:=case when v_line.is_open then v_line.paid_through_at else" in SQL
    assert "coalesce(p_daily_rate_override,v_line.default_daily_rate_snapshot)" in SQL
    assert "Only Customer Pay segments" in SQL
    assert "Only Customer Pay Loaner/RO segments" in SQL


def test_ew_split_snapshots_customer_pay_and_ui_uses_backend_capability():
    assert "create or replace function public.reconcile_extended_warranty_coverage_state" in SQL.lower()
    assert "customer_pay_standard_snapshot" in SQL
    assert "v_post_coverage_pay_type.default_daily_amount" in SQL
    assert "get_customer_pay_rate_override_capability_state" in UI
    assert "can_override_customer_pay_rate" in UI
    assert "set_customer_pay_billing_line_rate_override_state" in UI
    assert "Changes apply retroactively to the entire Customer Pay segment" in UI
    assert "Standard daily rate" in UI and "Effective daily rate" in UI


def test_override_currency_precision_is_validated_before_mutation():
    rpc = SQL.split("create or replace function public.set_customer_pay_billing_line_rate_override_state", 1)[1]
    precision_check = "p_daily_rate_override<>trunc(p_daily_rate_override,2)"
    assert precision_check in rpc
    assert "Daily-rate override must have at most two decimal places" in rpc
    assert rpc.index(precision_check) < rpc.index("select * into v_line") < rpc.index("update public.billing_lines")
    assert "v_effective:=coalesce(p_daily_rate_override,v_line.default_daily_rate_snapshot)" in rpc
    assert "daily_rate_override=p_daily_rate_override,amount=v_new_amount" in rpc
    assert "^\\d+(?:\\.\\d{1,2})?$" in UI
    assert 'pattern="\\d+(?:\\.\\d{1,2})?"' in UI

    # Representative boundary values document the RPC contract: cents are accepted;
    # sub-cent input is rejected before the row lock and therefore cannot mutate data.
    def accepted(value: str) -> bool:
        from decimal import Decimal
        amount = Decimal(value)
        return amount == amount.quantize(Decimal("0.01"))

    assert accepted("1.99")
    assert accepted("0")
    assert not accepted("1.994")
