from datetime import datetime, timezone
from pathlib import Path
import re


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


def predecessor_replacement(name: str) -> str:
    encoded = re.search(rf"{name} text := E'((?:''|[^'])*)';", PREDECESSOR).group(1)
    return encoded.replace("''", "'").replace(r"\n", "\n")


def splice_case_arm(definition: str, condition: str, replacement: str, occurrence: int = 1) -> str:
    starts = [match.start() for match in re.finditer(re.escape(condition), definition)]
    condition_at = starts[occurrence - 1]
    then_at = definition.index("THEN", condition_at)
    else_at = definition.index("ELSE", then_at)
    return definition[:then_at + 4] + "\n  " + replacement + "\n  " + definition[else_at:]


def compact(expression: str) -> str:
    """Mirror regexp_replace(value, '[[:space:]]', '', 'g')."""
    return re.sub(r"\s", "", expression)


def migration_expressions(definition: str) -> tuple[str, str, str]:
    """Reproduce the migration's branch counts, ordering, and CASE-arm extraction."""
    current_condition = "v_current_line.line_type = 'rental_extension'"
    history_condition = "parent.line_type = 'rental_extension'"
    assert len(re.findall(r"v_current_line\.line_type = 'rental_extension'", definition)) == 1
    assert len(re.findall(r"parent\.line_type = 'rental_extension'", definition)) == 2

    current_at = definition.index(current_condition)
    closed_at = definition.index(history_condition)
    active_at = definition.index(history_condition, closed_at + 1)
    assert closed_at < current_at < active_at

    def expression_at(condition_at: int) -> str:
        then_at = definition.index("THEN", condition_at)
        else_at = definition.index("ELSE", then_at)
        return compact(definition[then_at + 4:else_at])

    return expression_at(current_at), expression_at(closed_at), expression_at(active_at)


def migration_validation_state(definition: str) -> str:
    actual = migration_expressions(definition)
    old = tuple(compact(value) for value in re.findall(r"v_(?:current|closed|active)_old text := '([^']+)'", SQL))
    new = tuple(compact(value) for value in re.findall(r"v_(?:current|closed|active)_new text := '([^']+)'", SQL))
    if actual == new:
        return "target"
    if actual == old:
        return "predecessor"
    return "partial-or-drifted"


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
    assert SQL.count("v_current_line\\.line_type = ''rental_extension''") == 2
    assert SQL.count("parent\\.line_type = ''rental_extension''") == 2
    assert SQL.count("v_current_new text") == 1
    assert SQL.count("v_closed_new text") == 1
    assert SQL.count("v_active_new text") == 1
    assert "business_contract_days(v_reservation.start_date, v_preview_end) - public.business_contract_days(v_reservation.start_date, v_billing_start)" in SQL
    assert "business_contract_days(v_reservation.start_date, parent.start_time)" in SQL
    assert "never globally replace an expression" in SQL


def test_branch_count_patterns_use_one_postgresql_regex_escape():
    definition = "v_current_line.line_type = 'rental_extension'\n" + 2 * "parent.line_type = 'rental_extension'\n"
    assert len(re.findall(r"v_current_line\.line_type = 'rental_extension'", definition)) == 1
    assert len(re.findall(r"parent\.line_type = 'rental_extension'", definition)) == 2
    assert not re.findall(r"v_current_line\\.line_type = 'rental_extension'", definition)
    assert not re.findall(r"parent\\.line_type = 'rental_extension'", definition)
    assert SQL.count("v_current_line\\.line_type = ''rental_extension''") == 2
    assert SQL.count("parent\\.line_type = ''rental_extension''") == 2


def test_structural_splice_transforms_realistically_multiline_predecessor():
    fixture = "\n".join((
        predecessor_replacement("v_closed_replacement"),
        predecessor_replacement("v_current_replacement"),
        predecessor_replacement("v_active_replacement"),
    )).replace("(", "(\n                ").replace(", ", ",\n                ").replace(")", "\n            )")
    old_current = "greatest(0, public.business_contract_days(v_billing_start, v_preview_end) - 1)"
    assert old_current not in fixture  # pg_get_functiondef-style wrapping defeats one-line matching.

    targets = re.findall(r"v_(?:current|closed|active)_new text := '([^']+)'", SQL)
    assert len(targets) == 3
    assert migration_validation_state(fixture) == "predecessor"
    transformed = splice_case_arm(fixture, "parent.line_type = 'rental_extension'", targets[2], 2)
    transformed = splice_case_arm(transformed, "v_current_line.line_type = 'rental_extension'", targets[0])
    transformed = splice_case_arm(transformed, "parent.line_type = 'rental_extension'", targets[1])

    assert transformed.count("v_current_line.line_type = 'rental_extension'") == 1
    assert transformed.count("parent.line_type = 'rental_extension'") == 2
    for target in targets:
        assert transformed.count(target) == 1
    assert migration_validation_state(transformed) == "target"

    partial = splice_case_arm(fixture, "v_current_line.line_type = 'rental_extension'", targets[0])
    assert migration_validation_state(partial) == "partial-or-drifted"


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
