from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260827154000_rental_billing_workflow_ux.sql"


def test_warning_center_view_preserves_security_invoker():
    sql = MIGRATION.read_text(encoding="utf-8").lower()
    assert "create or replace view public.v_warning_center_warning_items" in sql
    assert "with (security_invoker = true) as" in sql
