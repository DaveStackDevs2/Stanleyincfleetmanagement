import re
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
MIGRATION = ROOT / "supabase/migrations/20260805120000_extended_warranty_live_billing_contract.sql"
FRONTEND = ROOT / "frontend/src/admin/PayTypeManagement.tsx"
DOCS = [ROOT / "docs/BILLING_BUILD_PUNCHLIST.md", ROOT / "recovery/updates/PROJECT_STATUS.md", ROOT / "recovery/updates/CHANGELOG.md"]

class ExtendedWarrantyLiveBillingContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text()
        cls.lower_sql = cls.sql.lower()
        cls.frontend = FRONTEND.read_text()
        cls.docs = "\n".join(path.read_text() for path in DOCS)

    def test_provider_rule_schema_contract(self):
        for text in [
            "alter column covered_days drop default", "alter column provider_id set not null",
            "alter column requires_approval set default false", "alter column requires_approval set not null",
            "ck_extended_warranty_rules_covered_days_positive", "covered_days is null or covered_days > 0",
            "ck_extended_warranty_rules_daily_rate_nonnegative_finite", "daily_rate is null or (daily_rate >= 0",
            "ux_extended_warranty_rules_one_active_per_provider", "where is_active = true",
            "ux_warranty_providers_name_normalized", "lower(btrim(name))",
        ]:
            self.assertIn(text, self.lower_sql)
        schema_section = self.lower_sql.split("create or replace function public.create_admin_extended_warranty_provider_rule_state", 1)[0]
        self.assertNotRegex(schema_section, r"insert\s+into\s+public\.extended_warranty_rules")
        self.assertNotRegex(schema_section, r"insert\s+into\s+public\.warranty_providers")
        self.assertNotIn("gm_warranty_rates", self.lower_sql)

    def test_case_schema_contract(self):
        for column in ["extended_warranty_rule_id uuid", "default_covered_days_snapshot integer", "default_daily_rate_snapshot numeric(12,2)", "coverage_started_at timestamptz", "coverage_exhausted_at timestamptz", "post_coverage_pay_type_rule_id uuid", "override_reason text", "override_authorized_by uuid", "override_authorized_at timestamptz", "updated_at timestamptz not null default now()"]:
            self.assertIn(column, self.lower_sql)
        for text in ["ux_warranty_cases_transportation_event_id", "on delete restrict", "warranty_cases_override_authorized_by_fkey", "on delete set null", "approved_days is null or approved_days > 0", "default_daily_rate_snapshot is null or (default_daily_rate_snapshot >= 0"]:
            self.assertIn(text, self.lower_sql)

    def test_permissions_security_owners_grants(self):
        self.assertIn("billing.extended_warranty_override", self.lower_sql)
        self.assertIn("can override the covered-day limit for an extended-warranty transportation case", self.lower_sql)
        self.assertIn("r.role_name in ('admin','dev')", self.lower_sql)
        for fn, sig in {
            "get_admin_billing_configuration_state": "",
            "create_admin_extended_warranty_provider_rule_state": "text,numeric,integer,boolean,text",
            "update_admin_extended_warranty_provider_rule_state": "uuid,text,numeric,integer,boolean,text",
            "set_admin_extended_warranty_provider_enabled_state": "uuid,boolean",
            "create_extended_warranty_case_and_get_state": "uuid,uuid",
            "set_extended_warranty_case_override_and_get_state": "uuid,integer,uuid,text",
            "reconcile_extended_warranty_coverage_state": "uuid,timestamptz",
            "reconcile_extended_warranty_coverage_and_get_state": "uuid",
        }.items():
            self.assertIn(f"function public.{fn}", self.lower_sql)
            self.assertIn("set search_path to ''", self.lower_sql)
            self.assertIn(f"alter function public.{fn}({sig}) owner to postgres", self.lower_sql)
            self.assertIn(f"revoke all on function public.{fn}({sig}) from public, anon, authenticated", self.lower_sql)
        self.assertIn("grant execute on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) to service_role", self.lower_sql)
        self.assertNotIn("grant execute on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) to authenticated", self.lower_sql)

    def test_runtime_boundaries(self):
        for text in ["auth.jwt() ->> 'aal'", "<> 'aal2'", "permission_key='billing.extended_warranty_override'", "insert into public.audit_log", "pay_type='Customer Pay'", "pay_type='Extended Warranty'", "public.business_contract_days", "public.close_billing_line_state", "public.create_billing_parent_line_state", "line_type='pay_type_split'", "p_extended_from_billing_line_id", "manual_review"]:
            self.assertIn(text, self.sql)
        for text in ["provider_type='extended_warranty'", "provider_type','extended_warranty'", "returning * into v_case", "clock_timestamp()", "approved_days", "effective_approved_days", "v_effective_at < v_boundary", "where transportation_event_id=p_transportation_event_id for update", "extended_warranty_coverage_split_already_exists", "extended_warranty_manual_review_missing_parent_line"]:
            self.assertIn(text, self.sql)
        self.assertIn("p_provider_id uuid", self.lower_sql)
        self.assertNotIn("p_rule_id", self.lower_sql)
        self.assertNotIn("p_default_daily_amount", self.lower_sql)
        self.assertNotIn("require_extended_warranty_actor_state", self.lower_sql)
        self.assertNotIn("on conflict (transportation_event_id) do update", self.lower_sql)
        self.assertNotIn("'Extended Warranty',p_default_daily_amount,true", self.sql)
        self.assertNotIn("warranty_day_ledger", self.lower_sql)
        self.assertNotRegex(self.sql, r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

    def test_frontend_rpc_only_no_delete(self):
        for rpc in ["get_admin_billing_configuration_state", "create_admin_extended_warranty_provider_rule_state", "update_admin_extended_warranty_provider_rule_state", "set_admin_extended_warranty_provider_enabled_state"]:
            self.assertIn(f"supabase.rpc('{rpc}'", self.frontend)
        self.assertIn("Extended Warranty Providers", self.frontend)
        self.assertIn("Blank means no automatic cap", self.frontend)
        self.assertIn("p_provider_id", self.frontend)
        self.assertNotIn("p_rule_id", self.frontend)
        self.assertIn("admin_extended_warranty_provider_enabled", self.frontend)
        self.assertIn("admin_extended_warranty_provider_disabled", self.frontend)
        self.assertIn("ExtendedWarrantyFocusMode", self.frontend)
        self.assertIn("Cancel / Return to Rates, Fees &amp; Billing Rules", self.frontend)
        self.assertIn("Return to Rates, Fees &amp; Billing Rules", self.frontend)
        self.assertIn("extendedWarrantyFocusMode === 'form'", self.frontend)
        self.assertIn("extendedWarrantyFocusMode === 'success'", self.frontend)
        self.assertIn("parseExtendedWarrantyState", self.frontend)
        self.assertNotIn("warranty_providers')", self.frontend)
        self.assertNotIn("extended_warranty_rules')", self.frontend)
        self.assertNotIn("Delete", self.frontend)

    def test_docs_record_status(self):
        for text in ["Extended Warranty provider/rule administration", "live contract/grants and static boundary checks passed", "provider/rule/case/billing tables had zero rows", "real-session/browser verification remains open"]:
            self.assertIn(text, self.docs)

if __name__ == '__main__':
    unittest.main()
