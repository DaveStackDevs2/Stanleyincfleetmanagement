import re
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
MIGRATION = ROOT / "supabase/migrations/20260804150000_phase_3_admin_rental_rate_rules.sql"
FRONTEND = ROOT / "frontend/src/admin/PayTypeManagement.tsx"

class Phase3RentalRateRulesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text()
        cls.lower_sql = cls.sql.lower()
        cls.frontend = FRONTEND.read_text()

    def test_schema_contract(self):
        for text in ["create table if not exists public.rental_rate_rules", "daily_rate numeric(12,2) not null", "alter column daily_rate type numeric(12,2)", "ck_rental_rate_rules_vehicle_class_nonblank", "ck_rental_rate_rules_daily_rate_nonnegative", "ck_rental_rate_rules_daily_rate_finite", "ck_rental_rate_rules_sort_order_nonnegative", "ck_rental_rate_rules_effective_range"]:
            self.assertIn(text, self.lower_sql)
        self.assertIn("owner to postgres", self.lower_sql)
        self.assertIn("enable row level security", self.lower_sql)
        self.assertIn("revoke all on table public.rental_rate_rules from public, anon, authenticated", self.lower_sql)
        self.assertIn("grant all on table public.rental_rate_rules to service_role", self.lower_sql)

    def test_indexes_trigger_and_no_seed(self):
        for text in ["ux_rental_rate_rules_current_class_pay_type", "where is_active = true and effective_to is null", "ix_rental_rate_rules_pay_type_rule_id", "ix_rental_rate_rules_created_by", "ix_rental_rate_rules_updated_by", "trg_rental_rate_rules_set_updated_at", "execute function public.set_updated_at()"]:
            self.assertIn(text, self.lower_sql)
        before_functions = self.lower_sql.split('create or replace function public.authorize_rental_rate_admin()', 1)[0]
        self.assertNotRegex(before_functions, r"insert\s+into\s+public\.rental_rate_rules")

    def test_function_contracts_security_and_grants(self):
        funcs = {
            "get_admin_rental_rate_rules_state": "",
            "create_admin_rental_rate_rule_state": "text, uuid, numeric, integer",
            "update_admin_rental_rate_rule_state": "uuid, text, uuid, numeric, integer",
            "set_admin_rental_rate_rule_enabled_state": "uuid, boolean",
            "resolve_rental_daily_rate_state": "text, uuid, timestamptz",
        }
        for name in funcs:
            self.assertIn(f"function public.{name}", self.lower_sql)
            self.assertIn("set search_path to ''", self.lower_sql)
            self.assertIn(f"alter function public.{name}({funcs[name]}) owner to postgres", self.lower_sql)
            self.assertIn(f"revoke all on function public.{name}({funcs[name]}) from public, anon, authenticated", self.lower_sql)
        self.assertIn("security definer", self.lower_sql)
        self.assertIn("security invoker", self.lower_sql)
        self.assertIn("grant execute on function public.resolve_rental_daily_rate_state(text, uuid, timestamptz) to service_role", self.lower_sql)
        self.assertNotIn("grant execute on function public.resolve_rental_daily_rate_state(text, uuid, timestamptz) to authenticated", self.lower_sql)

    def test_statuses_and_wall_clock_current_state(self):
        for status in ["admin_rental_rate_rules_ready", "admin_rental_rate_rule_created", "admin_rental_rate_rule_updated", "admin_rental_rate_rule_enabled", "admin_rental_rate_rule_disabled", "rental_daily_rate_pay_type_not_found", "rental_daily_rate_not_configured", "rental_daily_rate_resolved"]:
            self.assertIn(status, self.lower_sql)
        self.assertGreaterEqual(self.lower_sql.count("clock_timestamp()"), 4)
        self.assertIn("v_observed_at timestamptz := clock_timestamp()", self.lower_sql)
        self.assertIn("interval '1 microsecond'", self.lower_sql)

    def test_frontend_rpc_only_validation_no_delete_no_hardcoded_rates(self):
        for rpc in ["get_admin_rental_rate_rules_state", "create_admin_rental_rate_rule_state", "update_admin_rental_rate_rule_state", "set_admin_rental_rate_rule_enabled_state"]:
            self.assertIn(f"supabase.rpc('{rpc}'", self.frontend)
        self.assertNotIn("rental_rate_rules')", self.frontend)
        self.assertNotIn("Delete", self.frontend)
        self.assertIn("parseRentalRateState", self.frontend)
        self.assertIn("parseRentalRateMutation", self.frontend)
        self.assertIn("No rental rates are configured yet", self.frontend)
        self.assertIn("Number.isFinite(dailyRate)", self.frontend)
        self.assertIn("Vehicle class is free text", self.frontend)
        self.assertNotRegex(self.frontend, r"dailyRate:\s*\d")

if __name__ == '__main__':
    unittest.main()
