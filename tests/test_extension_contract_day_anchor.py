from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260820190000_anchor_extension_contract_days.sql"
SQL = MIGRATION.read_text()
PREDECESSOR = (ROOT / "supabase/migrations/20260820120000_verified_authoritative_extensions.sql").read_text()
CHECKPOINT = (ROOT / "supabase/migrations/20260810120000_authoritative_case_start_and_billed_through.sql").read_text()
UI = (ROOT / "frontend/src/billing/BillingWorkspace.tsx").read_text()


def business_contract_days(start: datetime, end: datetime) -> int:
    return max(1, int((end - start).total_seconds() // 86400) + 1)


def anchored_days(anchor: datetime, start: datetime, end: datetime) -> int:
    return max(0, business_contract_days(anchor, end) - business_contract_days(anchor, start))


def at(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def test_controlled_repeated_extension_timeline_keeps_reservation_anchor():
    anchor = at("2026-08-20T13:00:00Z")
    extension_start = at("2026-08-20T16:44:00Z")
    checkpoint = at("2026-08-20T19:43:00Z")
    current_return = at("2026-08-22T16:44:00Z")
    proposed_return = at("2026-08-23T16:44:00Z")

    assert anchored_days(anchor, extension_start, checkpoint) == 0
    assert anchored_days(anchor, extension_start, current_return) == 2
    assert anchored_days(anchor, extension_start, proposed_return) == 3
    assert anchored_days(anchor, checkpoint, proposed_return) == 3


def test_exactly_three_extension_branches_are_anchored_and_old_math_is_removed():
    # The source, idempotent-target, and post-splice guards each require the same
    # one-current/two-history branch shape in the generated function definition.
    assert SQL.count("v_current_line\\.line_type = ''rental_extension''") == 3
    assert SQL.count("parent\\.line_type = ''rental_extension''") == 3
    assert SQL.count("v_current_new text") == 1
    assert SQL.count("v_closed_new text") == 1
    assert SQL.count("v_active_new text") == 1
    assert "business_contract_days(v_reservation.start_date, v_preview_end) - public.business_contract_days(v_reservation.start_date, v_billing_start)" in SQL
    assert "business_contract_days(v_reservation.start_date, parent.start_time)" in SQL
    assert "do not globally replace SQL" in SQL


def test_non_extension_branches_and_protected_definitions_are_untouched():
    assert "ELSE public.business_contract_days(v_billing_start, v_preview_end)" in PREDECESSOR
    assert "ELSE public.business_contract_days(parent.start_time" in PREDECESSOR
    assert "mark_case_billed_through_and_get_preview_state" not in SQL
    assert "accept_case_extension_and_get_unified_payload_state" not in SQL
    assert "create_extension_billing_line_state" not in SQL
    assert "accept_extension_commit_state" not in SQL
    assert CHECKPOINT.count("mark_case_billed_through_and_get_preview_state") > 0


def test_security_and_idempotent_fail_closed_contract_are_preserved():
    for clause in (
        "OWNER TO postgres", "SECURITY DEFINER", "SET search_path TO ''",
        "REVOKE ALL", "GRANT EXECUTE", "TO authenticated",
        "chr(13)", "partial or drifted", "RETURN;",
    ):
        assert clause in SQL
    assert "INSERT " not in SQL and "UPDATE " not in SQL and "DELETE " not in SQL


def test_no_frontend_billing_arithmetic_was_added():
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    for arithmetic in ("preview.subtotal -", "preview.tax_amount +", "parseFloat", "toFixed"):
        assert arithmetic not in extension
