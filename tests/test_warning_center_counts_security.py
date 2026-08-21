from pathlib import Path


SQL = Path("supabase/migrations/20260821185500_secure_warning_center_counts.sql").read_text()
NORMALIZED = " ".join(SQL.split())


def test_warning_center_counts_is_service_role_only():
    assert "ALTER FUNCTION public.get_warning_center_counts_state() OWNER TO postgres;" in NORMALIZED
    assert "ALTER FUNCTION public.get_warning_center_counts_state() SECURITY DEFINER;" in NORMALIZED
    assert "ALTER FUNCTION public.get_warning_center_counts_state() SET search_path TO '';" in NORMALIZED
    assert (
        "REVOKE ALL ON FUNCTION public.get_warning_center_counts_state() "
        "FROM PUBLIC, anon, authenticated, service_role;"
    ) in NORMALIZED
    assert (
        "GRANT EXECUTE ON FUNCTION public.get_warning_center_counts_state() TO service_role;"
        in NORMALIZED
    )
    assert "TO authenticated;" not in NORMALIZED
    assert "TO anon;" not in NORMALIZED


def test_warning_center_counts_security_migration_does_not_replace_logic_or_write_data():
    upper = SQL.upper()
    assert "CREATE OR REPLACE FUNCTION" not in upper
    assert "INSERT INTO" not in upper
    assert "UPDATE " not in upper
    assert "DELETE FROM" not in upper
    assert "CREATE OR REPLACE VIEW" not in upper
