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
        before_functions = self.lower_sql.split('create or replace function public.get_admin_rental_rate_rules_state()', 1)[0]
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


    def test_no_extra_phase_3_helper_functions(self):
        self.assertNotIn("function public.authorize_rental_rate_admin", self.lower_sql)
        self.assertNotIn("function public.rental_rate_rule_json", self.lower_sql)
        self.assertGreaterEqual(len(re.findall(r"from\s+public\.app_users\s+au\s+where\s+au\.auth_user_id\s+=\s+auth\.uid\(\)\s+and\s+au\.is_active\s+=\s+true", self.lower_sql)), 4)
        self.assertGreaterEqual(self.lower_sql.count("permission_key = 'user_admin.manage'"), 4)

    def test_resolver_live_validation_payload_predicate_and_ordering(self):
        resolver = self.lower_sql.split("create or replace function public.resolve_rental_daily_rate_state", 1)[1].split("alter function public.get_admin", 1)[0]
        self.assertIn("stable security invoker set search_path to ''", resolver)
        self.assertIn("if p_vehicle_class is null or btrim(p_vehicle_class) = ''", resolver)
        self.assertIn("if p_pay_type_rule_id is null", resolver)
        self.assertIn("if p_effective_at is null", resolver)
        self.assertIn("using errcode='22023'", resolver)
        self.assertNotIn("coalesce(p_effective_at, now())", resolver)
        self.assertIn("and (r.is_active or r.effective_to is not null)", resolver)
        self.assertIn("order by r.effective_from desc, r.updated_at desc, r.id", resolver)
        for status in ["rental_daily_rate_pay_type_not_found", "rental_daily_rate_not_configured"]:
            status_tail = resolver.split(status, 1)[1][:500]
            self.assertIn("requested_vehicle_class", status_tail)
            self.assertIn("pay_type_rule_id", status_tail)
            self.assertIn("effective_at", status_tail)
        self.assertIn("v_vehicle_class := btrim(p_vehicle_class)", resolver)

    def test_disable_reactivate_live_locking_and_effective_window(self):
        fn = self.lower_sql.split("create or replace function public.set_admin_rental_rate_rule_enabled_state", 1)[1].split("create or replace function public.resolve_rental_daily_rate_state", 1)[0]
        self.assertIn("from public.rental_rate_rules where id = p_rental_rate_rule_id for update", fn)
        self.assertIn("where p.id = v_existing.pay_type_rule_id for share", fn)
        self.assertIn("v_effective_at := clock_timestamp()", fn)
        self.assertIn("when effective_to is not null then effective_to", fn)
        self.assertIn("effective_from + interval '1 microsecond'", fn)
        self.assertIn("effective_from=case when p_is_enabled and not is_active then v_effective_at else effective_from end", fn)

    def test_frontend_rpc_only_validation_no_delete_no_hardcoded_rates(self):
        # The Phase 3 database contracts remain in the migration for compatibility,
        # while the deployed Admin surface now uses the verified rate-card successors.
        for rpc in ["get_admin_rental_rate_cards_state", "create_admin_rental_rate_card_state", "update_admin_rental_rate_card_state", "set_admin_rental_rate_card_enabled_state"]:
            self.assertIn(f"supabase.rpc('{rpc}'", self.frontend)
        self.assertNotIn("rental_rate_rules')", self.frontend)
        self.assertNotIn("Delete", self.frontend)
        self.assertIn("parseRentalRateState", self.frontend)
        self.assertIn("parseRentalRateMutation", self.frontend)
        self.assertIn("No current Rental models are configured or referenced", self.frontend)
        self.assertIn("Number.isFinite(dailyRate)", self.frontend)
        self.assertIn("Vehicle class / model identifier", self.frontend)
        self.assertIn("changed, but authoritative settings could not be reloaded", self.frontend)
        self.assertNotRegex(self.frontend, r"dailyRate:\s*\d")

if __name__ == '__main__':
    unittest.main()
