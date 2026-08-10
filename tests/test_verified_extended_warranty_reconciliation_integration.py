import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).parents[1]
SQL = (ROOT / "supabase/migrations/20260810130000_verified_extended_warranty_reconciliation_integration.sql").read_text()
LOWER = SQL.lower()
UI = (ROOT / "frontend/src/billing/BillingWorkspace.tsx").read_text()
ENGINE = (ROOT / "supabase/migrations/20260805120000_extended_warranty_live_billing_contract.sql").read_text()


class VerifiedExtendedWarrantyReconciliationIntegration(unittest.TestCase):
    def body(self, name):
        return SQL.split(f"create or replace function public.{name}", 1)[1].split("$function$;", 1)[0]

    def test_permission_is_idempotent_and_dev_role_is_name_based(self):
        self.assertIn("'billing.extended_warranty_reconcile'", SQL)
        self.assertIn("on conflict (permission_key) do update", LOWER)
        self.assertIn("role.role_name = 'Dev'", SQL)
        self.assertIn("on conflict do nothing", LOWER)
        self.assertNotRegex(SQL, r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
        self.assertNotRegex(LOWER, r"role_name\s*=\s*'admin'")

    def test_internal_payload_engine_boundary(self):
        signature = "public.reconcile_extended_warranty_coverage_and_get_state(uuid)"
        for token in ("owner to postgres", "security definer", "set search_path to ''"):
            self.assertRegex(LOWER, rf"alter function {re.escape(signature)}\s+{token}")
        self.assertRegex(LOWER, rf"revoke all on function {re.escape(signature)}\s+from public, anon, authenticated, service_role")
        self.assertRegex(LOWER, rf"grant execute on function {re.escape(signature)}\s+to postgres, service_role")
        self.assertIn("pg_get_functiondef(v_function)", SQL)

    def test_explicit_wrapper_has_active_permission_and_aal2_checks(self):
        name = "reconcile_extended_warranty_coverage_and_get_payload_state"
        body = self.body(name)
        for token in ("p_transportation_event_id is null", "auth.uid()", "app_user.is_active = true", "v_user_effective_permissions", "billing.extended_warranty_reconcile", "auth.jwt() ->> 'aal'", "<> 'aal2'", "reconcile_extended_warranty_coverage_and_get_state"):
            self.assertIn(token, body)
        self.assertNotIn("Admin", body)
        self.assertRegex(LOWER, rf"revoke all on function public\.{name}\(uuid\)\s+from public, anon, authenticated, service_role")
        self.assertRegex(LOWER, rf"grant execute on function public\.{name}\(uuid\)\s+to authenticated, service_role")

    def test_workspace_orchestrator_is_deterministic_and_not_aal2(self):
        name = "get_reconciled_billing_workspace_state"
        body = self.body(name)
        for token in ("p_effective_at is null", "p_effective_at > v_now", "auth.uid()", "app_user.is_active = true", "v_user_effective_permissions", "billing.extended_warranty_reconcile", "lower(btrim(transportation_event.status)) = 'active'", "from public.warranty_cases", "order by transportation_event.id", "reconcile_extended_warranty_coverage_state", "return public.get_billing_workspace_state(p_effective_at)"):
            self.assertIn(token, body)
        self.assertNotIn("auth.jwt()", body)
        self.assertNotIn("Admin", body)
        self.assertLess(body.index("perform public.reconcile_extended_warranty_coverage_state"), body.index("return public.get_billing_workspace_state"))
        self.assertRegex(LOWER, rf"grant execute on function public\.{name}\(timestamptz\)\s+to authenticated, service_role")

    def test_frontend_replaces_workspace_rpc_without_direct_tables(self):
        self.assertIn("supabase.rpc('get_reconciled_billing_workspace_state'", UI)
        self.assertNotIn("supabase.rpc('get_billing_workspace_state'", UI)
        for forbidden in (".from(", ".insert(", ".update(", ".delete("):
            self.assertNotIn(forbidden, UI)
        for preserved in ("parseWorkspace(result.data)", "formatExactMoney", "keepSelected", "mark_case_billed_through_and_get_preview_state", "attentionReason"):
            self.assertIn(preserved, UI)

    def test_existing_engine_preserves_timer_split_and_gm_separation(self):
        reconcile = ENGINE.split("CREATE OR REPLACE FUNCTION public.reconcile_extended_warranty_coverage_state", 1)[1].split("AS $function$", 1)[1].split("$function$", 1)[0]
        self.assertIn("v_case.coverage_started_at", reconcile)
        self.assertIn("public.business_contract_days", reconcile)
        self.assertIn("v_current_line.vehicle_event_id", reconcile)
        self.assertIn("'extended_warranty_coverage_cap'", reconcile)
        self.assertIn("v_existing_split", reconcile)
        self.assertIn("extended_warranty_coverage_already_split", reconcile)
        self.assertRegex(reconcile, r"coalesce\(\s*v_case\.approved_days")
        self.assertNotIn("gm_warranty", reconcile.lower())
        self.assertNotIn("round(", reconcile.lower())

    def test_migration_contains_no_operational_seed_values(self):
        for forbidden in ("Zurich", "$40", "40.00", "10-day", "10 day", "insert into public.warranty_providers", "insert into public.extended_warranty_rules", "insert into public.warranty_cases"):
            self.assertNotIn(forbidden, SQL)


if __name__ == "__main__":
    unittest.main()
