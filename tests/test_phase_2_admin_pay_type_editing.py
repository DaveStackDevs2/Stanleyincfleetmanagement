import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
MIGRATION = ROOT / "supabase/migrations/20260804120000_phase_2_admin_pay_type_editing.sql"
FRONTEND = ROOT / "frontend/src/admin/PayTypeManagement.tsx"
FUNCTION = "public.update_admin_pay_type_rule_state"
TYPES = ["uuid", "boolean", "numeric", "integer", "text"]


class Phase2PayTypeEditingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text()
        cls.lower_sql = cls.sql.lower()
        cls.frontend = FRONTEND.read_text()

    def test_function_identity_is_consistent(self) -> None:
        create = re.search(rf"create or replace function\s+{re.escape(FUNCTION)}\((.*?)\)\s+returns", self.sql, re.I | re.S)
        self.assertIsNotNone(create)
        create_types = [part.strip().split()[1].lower() for part in create.group(1).split(",")]
        self.assertEqual(TYPES, create_types)
        identities = re.findall(rf"(?:alter function|revoke all on function|grant execute on function)\s+{re.escape(FUNCTION)}\((.*?)\)\s+(?:owner|from|to)", self.sql, re.I | re.S)
        self.assertEqual(3, len(identities))
        self.assertTrue(all([part.strip().lower() for part in identity.split(",")] == TYPES for identity in identities))

    def test_security_and_authorization_contract(self) -> None:
        self.assertIn("security definer", self.lower_sql)
        self.assertIn("set search_path to ''", self.lower_sql)
        self.assertIn("au.auth_user_id = auth.uid()", self.lower_sql)
        self.assertIn("au.is_active = true", self.lower_sql)
        self.assertIn("get_user_admin_setting_access_state", self.lower_sql)
        self.assertIn("'fleet_board.pay_type_colors'", self.lower_sql)
        self.assertIn("revoke all", self.lower_sql)
        self.assertIn("to authenticated, service_role", self.lower_sql)

    def test_backend_validation_and_assignments(self) -> None:
        for text in ["p_pay_type_rule_id is null", "p_is_taxable is null", "p_sort_order is null or p_sort_order < 0", "p_default_daily_amount < 0"]:
            self.assertIn(text, self.lower_sql)
        update = re.search(r"update public\.pay_type_rules\s+set(.*?)where id", self.lower_sql, re.S).group(1)
        self.assertIn("is_taxable = p_is_taxable", update)
        self.assertIn("tax_applicable = p_is_taxable", update)
        self.assertIn("description = nullif(btrim(p_description), '')", update)
        self.assertIn("updated_at = now()", update)
        self.assertNotRegex(update, r"(?m)^\s*(pay_type|active|is_active)\s*=")

    def test_deterministic_response_contract(self) -> None:
        self.assertIn("'status', 'admin_pay_type_rule_updated'", self.lower_sql)
        for field in ["pay_type_rule_id", "pay_type", "is_enabled", "is_active", "active", "is_taxable", "tax_applicable", "default_daily_amount", "sort_order", "description"]:
            self.assertIn(f"'{field}'", self.lower_sql)

    def test_frontend_updates_without_rename_and_verifies_reload(self) -> None:
        call = re.search(r"supabase\.rpc\('update_admin_pay_type_rule_state',\s*\{(.*?)\}\)", self.frontend, re.S).group(1)
        self.assertIn("p_pay_type_rule_id", call)
        self.assertNotIn("p_pay_type:", call)
        self.assertIn("parseUpdatedPayType(result.data, editForm.id)", self.frontend)
        self.assertIn("const reloaded = await load()", self.frontend)
        self.assertIn("was updated successfully", self.frontend)
        self.assertIn("may have changed; refresh before trying again", self.frontend)
        self.assertIn('role="alert"', self.frontend)
        self.assertIn('role="status" aria-live="polite"', self.frontend)


if __name__ == "__main__":
    unittest.main()
