import re
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
BASE = ROOT / "supabase/migrations/20260805120000_extended_warranty_live_billing_contract.sql"
FOLLOWUP = ROOT / "supabase/migrations/20260805123000_extended_warranty_mandatory_provider_cap.sql"
FRONTEND = ROOT / "frontend/src/admin/PayTypeManagement.tsx"
DOCS = [ROOT / "docs/BILLING_BUILD_PUNCHLIST.md", ROOT / "recovery/updates/PROJECT_STATUS.md", ROOT / "recovery/updates/CHANGELOG.md"]

class ExtendedWarrantyMandatoryProviderCapFollowupTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = FOLLOWUP.read_text()
        cls.lower_sql = cls.sql.lower()
        cls.base = BASE.read_text()
        cls.lower_base = cls.base.lower()
        cls.frontend = FRONTEND.read_text()
        cls.docs = "\n".join(path.read_text() for path in DOCS)

    def test_followup_migration_is_idempotent_and_narrow(self):
        self.assertIn("alter column covered_days set not null", self.lower_sql)
        self.assertIn("drop constraint if exists ck_extended_warranty_rules_provider_approval_disabled", self.lower_sql)
        self.assertIn("add constraint ck_extended_warranty_rules_provider_approval_disabled check (requires_approval = false)", self.lower_sql)
        self.assertEqual(self.lower_sql.count("create or replace function public.create_admin_extended_warranty_provider_rule_state"), 1)
        self.assertEqual(self.lower_sql.count("create or replace function public.update_admin_extended_warranty_provider_rule_state"), 1)
        for fn in ["set_admin_extended_warranty_provider_enabled_state", "create_extended_warranty_case_and_get_state", "set_extended_warranty_case_override_and_get_state", "reconcile_extended_warranty_coverage_state", "reconcile_extended_warranty_coverage_and_get_state"]:
            self.assertNotIn(f"create or replace function public.{fn}", self.lower_sql)

    def test_admin_mutation_rpcs_require_caps_reject_approval_store_false(self):
        self.assertEqual(self.sql.count("IF p_covered_days IS NULL OR p_covered_days <= 0 THEN"), 2)
        self.assertEqual(self.sql.count("Covered-day cap must be a positive whole number"), 2)
        self.assertEqual(self.sql.count("IF p_requires_approval IS DISTINCT FROM false THEN"), 2)
        self.assertEqual(self.sql.count("Provider-level approval is not supported; use an authorized case override for coverage extensions"), 2)
        self.assertIn("requires_approval,\n      daily_rate", self.sql)
        self.assertIn("p_covered_days,\n      false,\n      NULL", self.sql)
        self.assertIn("requires_approval = false", self.sql)
        self.assertNotIn("Covered-day cap must be blank", self.sql)
        self.assertNotIn("Provider approval selection is required", self.sql)
        self.assertNotIn("requires_approval = p_requires_approval", self.sql)

    def test_security_owner_search_path_revoke_grant_boundaries(self):
        for sig in ["create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text)", "update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text)"]:
            self.assertIn("security definer", self.lower_sql)
            self.assertIn("set search_path to ''", self.lower_sql)
            self.assertIn(f"alter function public.{sig} owner to postgres", self.lower_sql)
            self.assertIn(f"revoke all on function public.{sig} from public, anon, authenticated", self.lower_sql)
            self.assertIn(f"grant execute on function public.{sig} to authenticated, service_role", self.lower_sql)
            self.assertNotIn(f"grant execute on function public.{sig} to public", self.lower_sql)
            self.assertNotIn(f"grant execute on function public.{sig} to anon", self.lower_sql)

    def test_case_override_runtime_contract_remains_in_base(self):
        for text in ["billing.extended_warranty_override", "set_extended_warranty_case_override_and_get_state", "approved_days", "covered_days_override"]:
            self.assertIn(text, self.base)
        self.assertNotIn("set_extended_warranty_case_override_and_get_state", self.sql)

    def test_frontend_mandatory_cap_contract(self):
        self.assertIn("p_requires_approval: false", self.frontend)
        self.assertIn("typeof item.requires_approval !== 'boolean' || item.requires_approval !== false", self.frontend)
        self.assertIn("<label>Covered-day cap<input required min=\"1\" step=\"1\" type=\"number\"", self.frontend)
        self.assertIn("Enter the provider's normal covered-day limit. Exceptional extensions use an authorized case override.", self.frontend)
        self.assertIn("Each provider must have a normal covered-day limit. Exceptional shorter or longer coverage uses an authorized case override.", self.frontend)
        for forbidden in ["Requires approval", "requiresApproval", "Optional covered-day cap", "blank means", "Blank means", "No automatic cap", "unlimited", "Unlimited"]:
            self.assertNotIn(forbidden, self.frontend)

    def test_no_business_values_or_crossovers_introduced(self):
        combined = self.sql + "\n" + self.frontend
        self.assertNotIn("gm_warranty_rates", self.lower_sql)
        self.assertNotIn("GM Warranty", self.sql)
        self.assertNotRegex(combined, r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
        self.assertNotRegex(self.sql, r"insert\s+into\s+public\.warranty_providers", re.I)
        self.assertNotRegex(self.sql, r"insert\s+into\s+public\.extended_warranty_rules", re.I)

    def test_docs_record_verified_live_and_open_browser_verification(self):
        for text in ["live mandatory-cap contract was verified before repository work", "real authenticated mutation/browser verification remains open"]:
            self.assertIn(text, self.docs)

if __name__ == '__main__':
    unittest.main()
