import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).parents[1]
SQL = (ROOT / "supabase/migrations/20260810120000_authoritative_case_start_and_billed_through.sql").read_text()
UI = (ROOT / "frontend/src/billing/BillingWorkspace.tsx").read_text()

class AuthoritativeBillingContractTests(unittest.TestCase):
    def test_permissions_are_effective_and_dev_assignment_is_name_based(self):
        self.assertIn("billing.case_start", SQL)
        self.assertIn("billing.mark_billed_through", SQL)
        self.assertIn("r.role_name = 'Dev'", SQL)
        self.assertIn("v_user_effective_permissions", SQL)
        self.assertNotRegex(SQL.lower(), r"role_name\s*=\s*'admin'")

    def test_security_boundary(self):
        for function in ("create_authoritative_start_bill_case_state", "mark_case_billed_through_and_get_preview_state"):
            body = SQL[SQL.index("create or replace function public." + function):]
            self.assertIn("security definer set search_path to ''", body)
            self.assertIn("owner to postgres", body)
            self.assertRegex(body, rf"revoke all on function public\.{function}[^;]+from public, anon, authenticated, service_role")
            self.assertRegex(body, rf"grant execute on function public\.{function}[^;]+to authenticated, service_role")
        self.assertIn("au.auth_user_id = auth.uid()", SQL)
        self.assertIn("au.is_active = true", SQL)
        self.assertNotIn("auth.jwt()", SQL)

    def test_start_has_no_caller_totals_or_actor_and_reuses_engines(self):
        signature = SQL.split(") returns jsonb", 1)[0]
        for forbidden in ("amount", "tax", "rate", "actor"):
            self.assertNotIn("p_" + forbidden, signature)
        for engine in ("create_reservation_with_transportation_event_state", "start_vehicle_use_state", "get_billing_preview_state", "create_billing_parent_line_state", "ensure_tax_child_line_state"):
            self.assertIn(engine, SQL)
        self.assertIn("'active'", SQL)
        self.assertIn("'billing_line_id',v_line_id", SQL)
        self.assertIn("authoritative_case_created_started_billed", SQL)

    def test_checkpoint_is_monotonic_exact_synchronized_and_open(self):
        for phrase in ("cannot be in the future", "cannot precede case start", "cannot move backward", "exactly one open parent billing segment"):
            self.assertIn(phrase, SQL)
        self.assertIn("get_billing_preview_state(v_res.transportation_event_id,p_billed_through_at)", SQL)
        self.assertIn("set_reservation_billed_through_state", SQL)
        self.assertIn("ensure_tax_child_line_state", SQL)
        self.assertIn("paid_through_at=p_billed_through_at", SQL)
        self.assertIn("is_open=true", SQL)
        self.assertIn("checkpoint_subtotal',v_preview->>'subtotal'", SQL)
        self.assertIn("billing_checkpoint_recorded", SQL)

    def test_low_level_and_obsolete_grants_are_revoked(self):
        self.assertRegex(SQL, r"revoke execute on function public\.create_start_bill_case_and_get_payload_state[\s\S]+from authenticated")
        self.assertIn("revoke all on function public.set_reservation_billed_through_state(uuid,timestamptz,text) from public, anon, authenticated", SQL)
        self.assertIn("to postgres, service_role", SQL)

    def test_frontend_rpc_validation_reload_and_sanitized_messages(self):
        self.assertIn("supabase.rpc('mark_case_billed_through_and_get_preview_state'", UI)
        self.assertIn("checkpointKeys", UI)
        self.assertIn("validCheckpoint", UI)
        self.assertIn("await onReload(item.transportation_event_id)", UI)
        self.assertIn("You do not have permission", UI)
        self.assertIn("date.getTime()>Date.now()", UI)
        self.assertIn("onClick={()=>void submit()}", UI)
        self.assertNotIn("useEffect(()=>{void submit", UI)
        self.assertIn("keepSelected", UI)
        self.assertNotRegex(UI, r"\.from\(['\"](?:permissions|role_permissions)")

    def test_exact_formatter_examples_and_no_rounding(self):
        # Verify the source transformation without importing TypeScript.
        def fmt(value):
            self.assertRegex(value, r"^-?(0|[1-9]\d*)(\.\d+)?$")
            whole, _, fraction = value.partition(".")
            if len(fraction) <= 2: return whole + "." + fraction.ljust(2, "0")
            return whole + "." + fraction.rstrip("0").ljust(2, "0")
        for raw, expected in (("28.0000","28.00"),("308.0000","308.00"),("4.0050","4.005"),("7","7.00"),("-2.500","-2.50")):
            self.assertEqual(fmt(raw), expected)
        for malformed in ("", ".5", "01", "1.", "NaN", "$2"):
            with self.assertRaises(AssertionError): fmt(malformed)
        for api in ("parseFloat", ".toFixed(", "Math.round"):
            self.assertNotIn(api, UI)

    def test_no_controlled_fixture_leakage(self):
        production = SQL + UI
        for forbidden in ("1010101", "Test Customer", "Test Model", "$40"):
            self.assertNotIn(forbidden, production)

if __name__ == '__main__': unittest.main()
