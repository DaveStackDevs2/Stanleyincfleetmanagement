import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).parents[1]
SQL = (ROOT / 'supabase/migrations/20260810140000_verified_billing_case_completion.sql').read_text()
UI = (ROOT / 'frontend/src/billing/BillingWorkspace.tsx').read_text()
PRIOR = (ROOT / 'functions_export.sql').read_text().lower()


class VerifiedBillingCaseCompletionTests(unittest.TestCase):
    def test_idempotent_permission_and_dev_role_assignment(self):
        self.assertIn("'billing.case_complete'", SQL)
        self.assertIn('on conflict (permission_key) do update', SQL)
        self.assertIn("role.role_name = 'Dev'", SQL)
        self.assertIn("permission.permission_key = 'billing.case_complete'", SQL)
        self.assertIn('on conflict do nothing', SQL)
        self.assertNotRegex(SQL, r"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
        self.assertNotRegex(SQL.lower(), r"role_name\s*=\s*'admin'")

    def test_exact_permission_gate_and_security_boundary(self):
        active = SQL.index('if v_user_id is null')
        aal2 = SQL.index("auth.jwt() ->> 'aal'")
        permission = SQL.index('if not exists (')
        mismatch = SQL.index('if p_closed_by is not null')
        self.assertLess(active, aal2)
        self.assertLess(aal2, permission)
        self.assertLess(permission, mismatch)
        self.assertIn('from public.v_user_effective_permissions permission', SQL)
        self.assertIn('permission.user_id = v_user_id', SQL)
        self.assertIn("raise exception 'Case completion permission is required'", SQL)
        self.assertIn("using errcode = '42501'", SQL)
        self.assertIn('security definer', SQL)
        self.assertIn("set search_path to ''", SQL)
        self.assertIn('owner to postgres', SQL)
        self.assertRegex(SQL, r'revoke all on function public\.complete_case_and_get_unified_payload_state[\s\S]+from public, anon, authenticated, service_role')
        self.assertRegex(SQL, r'grant execute on function public\.complete_case_and_get_unified_payload_state[\s\S]+to authenticated;')

    def test_wrapper_contract_and_internal_engines_are_preserved(self):
        self.assertIn('au.auth_user_id = auth.uid()', SQL)
        self.assertIn('au.is_active = true', SQL)
        self.assertIn('coalesce(p_end_mileage, v_existing_end_mileage)', SQL)
        self.assertIn('public.complete_case_return_and_close_state(', SQL)
        self.assertIn('public.get_unified_case_payload_state(p_reservation_id)', SQL)
        self.assertIn("'status', 'case_completed_and_loaded'", SQL)
        for engine in ('return_reservation_vehicle_use_state', 'close_current_reservation_billing_line_state', 'close_transportation_event_state'):
            self.assertNotIn(f'create or replace function public.{engine}', SQL)
        self.assertIn('create or replace function public.complete_case_return_and_close_state', PRIOR)
        self.assertNotIn('create or replace function public.complete_case_return_and_close_state', SQL)

    def test_focused_navigation_optional_mileage_and_rpc_only_mutation(self):
        self.assertIn('completionItem?<CompletionAction', UI)
        self.assertIn('Cancel / Return to Billing', UI)
        self.assertIn('Return to Billing Dashboard', UI)
        self.assertIn('Optional return mileage', UI)
        self.assertIn("trimmedMileage===''?null:Number(trimmedMileage)", UI)
        self.assertIn("!/^\\d+$/.test(trimmedMileage)", UI)
        self.assertIn('Number.isSafeInteger(parsedMileage)', UI)
        self.assertIn("Number.isNaN(date.getTime())||date.getTime()>Date.now()", UI)
        self.assertIn("valid actual return date and time that is not in the future", UI)
        self.assertRegex(UI, r'Actual return date and time<input[^>]+max=\{localNow\(\)\}')
        entry = '<CaseHeader item={item}/>{item.reservation.reservation_id&&<button type="button" className="primary-action completion-entry"'
        attention = "{p.status!=='billing_preview_ready'?"
        self.assertIn(entry, UI)
        self.assertLess(UI.index(entry), UI.index(attention, UI.index(entry)))
        self.assertNotIn('<ReadySummary item={item} p={p}/><button type="button" className="primary-action completion-entry"', UI)
        self.assertIn("supabase.rpc('complete_case_and_get_unified_payload_state'", UI)
        self.assertNotRegex(UI, r"\.from\(['\"](?:reservations|transportation_events|billing_lines|vehicle_events)")

    def test_complete_request_response_and_authoritative_reload(self):
        for contract in ("p_reservation_id:reservation", 'p_actual_in_at:actualInAt', 'p_end_mileage:parsedMileage', 'p_close_billing:true', "p_close_note:note.trim()||null", 'p_closed_by:null'):
            self.assertIn(contract, UI)
        for field in ('case_completed_and_loaded', 'case_returned_and_closed', 'transportation_event_id', 'actual_in_at', 'unified_case_payload'):
            self.assertIn(field, UI)
        self.assertIn('setMutationAccepted(true);const reloaded=await onComplete()', UI)
        self.assertIn('const locked=busy||mutationAccepted', UI)
        self.assertIn('await onComplete()', UI)
        self.assertIn('onComplete={async()=>{const reloaded=await load();', UI)
        self.assertIn("supabase.rpc('get_reconciled_billing_workspace_state'", UI)
        self.assertIn("result.error?.code==='42501'", UI)

    def test_money_and_fixture_boundaries(self):
        for api in ('parseFloat', '.toFixed(', 'Math.round'):
            self.assertNotIn(api, UI)
        production = SQL + UI
        for fixture in ('Test Customer', 'Test Vehicle', 'Test Model', '1010101', '$40'):
            self.assertNotIn(fixture, production)


if __name__ == '__main__':
    unittest.main()
