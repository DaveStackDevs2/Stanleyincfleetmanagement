from pathlib import Path

ROOT = Path(__file__).parents[1]
SQL = (ROOT / "supabase/migrations/20260819143500_verified_closed_billing_review.sql").read_text()
UI = (ROOT / "frontend/src/billing/BillingWorkspace.tsx").read_text()


def test_preview_is_extended_with_stored_history():
    assert "pg_get_functiondef(v_preview)" in SQL
    assert "stored_closed_billing_snapshot" in SQL
    assert "public.billing_lines" in SQL
    assert "billing_preview_ready" in SQL
    assert "sum(parent.amount)" in SQL and "sum(parent.tax_amount)" in SQL
    assert "Closed billing uses stored historical line snapshots without recalculation." in SQL
    assert "resolve_rental_daily_rate_state" not in SQL


def test_final_wrapper_delegates_and_filters_closed_at():
    assert "get_reservation_lifecycle_list_state()" in SQL
    assert "get_billing_preview_state((v_case->>'transportation_event_id')::uuid" in SQL
    assert "('all','rental','loaner')" in SQL
    assert "'date_field','transportation_event.closed_at'" in SQL
    assert ">= p_closed_from" in SQL
    assert "< p_closed_before" in SQL
    assert "v_limit < 1 OR v_limit > 200" in SQL
    assert "DROP FUNCTION IF EXISTS public.get_closed_billing_workspace_state(integer)" in SQL


def test_security_metadata_and_grants():
    signature = "get_closed_billing_workspace_state(text,timestamptz,timestamptz,integer)"
    assert f"ALTER FUNCTION public.{signature} OWNER TO postgres" in SQL
    assert f"ALTER FUNCTION public.{signature} SECURITY DEFINER" in SQL
    assert f"ALTER FUNCTION public.{signature} SET search_path TO ''" in SQL
    assert f"REVOKE ALL ON FUNCTION public.{signature} FROM PUBLIC, anon, authenticated, service_role" in SQL
    assert f"GRANT EXECUTE ON FUNCTION public.{signature} TO authenticated" in SQL
    assert "auth.jwt()->>'aal'" in SQL and "app_user.is_active=true" in SQL


def test_frontend_rpc_only_exact_money_contract():
    assert "Active cases" in UI and "Closed cases" in UI
    assert "get_reconciled_billing_workspace_state" in UI
    assert "get_closed_billing_workspace_state" in UI
    for forbidden in (".from(", ".insert(", ".update(", ".delete(", "Math.round", "toFixed", "parseFloat"):
        assert forbidden not in UI
    assert "formatExactMoney" in UI and "money(v" in UI


def test_closed_filters_and_read_only_history():
    for text in ("All", "Rental", "Loaner", "Case closed date (Transportation Event)", "Showing up to 50 matching closed cases."):
        assert text in UI
    assert "throughBefore" in UI and "local.setDate(local.getDate()+1)" in UI
    assert "Every stored billing segment" in UI
    assert "s.contract_days" in UI and "p.segments.map" in UI
    closed_detail = UI[UI.index("function ClosedDetail"):UI.index("const throughBefore")]
    assert "Complete / Return Case" not in closed_detail
    assert "Mark billed through" not in closed_detail
