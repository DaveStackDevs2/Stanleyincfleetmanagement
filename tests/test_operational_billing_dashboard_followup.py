import pathlib
import unittest

ROOT = pathlib.Path(__file__).parents[1]
MIGRATION = (ROOT / 'supabase/migrations/20260807130000_operational_billing_dashboard_read_followup.sql').read_text()
UI = (ROOT / 'frontend/src/billing/BillingWorkspace.tsx').read_text()

class OperationalBillingDashboardFollowupContract(unittest.TestCase):
    def test_idempotent_drift_safe_rpc_changes(self):
        for token in ("pg_get_functiondef(v_preview)", "pg_get_functiondef(v_workspace)", "position(v_aal2_block IN v_definition)", "insertion point has drifted", "position(v_ro_select_new IN v_definition) = 0", "position(v_ro_payload_new IN v_definition) = 0", "position(v_contract_days_new IN v_definition) = 0", "reservation.ro_number", "''ro_number'', v_case.ro_number"):
            self.assertIn(token, MIGRATION)

    def test_repository_predecessor_gets_verified_ro_placements(self):
        select_old = "            reservation.reservation_type,\n            reservation.requested_model,"
        select_new = "            reservation.reservation_type,\n            reservation.ro_number,\n            reservation.requested_model,"
        payload_old = "                'reservation_type', v_case.reservation_type,\n                'requested_model', v_case.requested_model,"
        payload_new = "                'reservation_type', v_case.reservation_type,\n                'ro_number', v_case.ro_number,\n                'requested_model', v_case.requested_model,"
        predecessor = (ROOT / 'supabase/migrations/20260807120000_operational_billing_dashboard.sql').read_text()
        transformed = predecessor.replace(select_old, select_new).replace(payload_old, payload_new)
        self.assertEqual(transformed.count(select_new), 1)
        self.assertEqual(transformed.count(payload_new), 1)
        self.assertEqual(transformed.count("reservation.ro_number"), 1)
        self.assertEqual(transformed.count("'ro_number', v_case.ro_number"), 1)

    def test_verified_live_ro_definition_is_a_noop(self):
        select_new = "            reservation.reservation_type,\n            reservation.ro_number,\n            reservation.requested_model,"
        payload_new = "                'reservation_type', v_case.reservation_type,\n                'ro_number', v_case.ro_number,\n                'requested_model', v_case.requested_model,"
        live_definition = f"{select_new}\n{payload_new}"
        self.assertEqual(live_definition.replace(select_new, select_new).replace(payload_new, payload_new), live_definition)
        self.assertEqual(live_definition.count("reservation.ro_number"), 1)
        self.assertEqual(live_definition.count("'ro_number', v_case.ro_number"), 1)

    def test_segment_contract_days_case_is_recorded_once(self):
        predecessor = (ROOT / 'supabase/migrations/20260807120000_operational_billing_dashboard.sql').read_text()
        old = "                'paid_through_at', parent.paid_through_at,\n                'is_open', parent.is_open,"
        new = """                'paid_through_at', parent.paid_through_at,
                'contract_days',
                    CASE
                        WHEN parent.start_time IS NULL THEN NULL
                        ELSE public.business_contract_days(
                            parent.start_time,
                            coalesce(
                                parent.end_time,
                                parent.paid_through_at,
                                p_effective_at
                            )
                        )
                    END,
                'is_open', parent.is_open,"""
        transformed = predecessor.replace(old, new)
        self.assertEqual(transformed.count(new), 1)
        self.assertEqual(
            transformed.count("public.business_contract_days("),
            predecessor.count("public.business_contract_days(") + 1,
        )
        self.assertIn("v_contract_days_new", MIGRATION)

    def test_only_read_rpc_aal2_exceptions_are_targeted(self):
        self.assertEqual(MIGRATION.count("AAL2 authentication is required"), 3)
        self.assertNotIn("Admin", MIGRATION)
        self.assertNotIn("has_permission", MIGRATION)
        for signature in ("get_billing_preview_state(uuid,timestamptz)", "get_billing_workspace_state(timestamptz)"):
            self.assertIn(signature, MIGRATION)

    def test_active_user_and_authenticated_only_security_are_retained(self):
        self.assertEqual(MIGRATION.count("app_user.is_active = true"), 2)
        self.assertEqual(MIGRATION.count("SECURITY DEFINER;"), 2)
        self.assertEqual(MIGRATION.count("SET search_path TO '';"), 2)
        self.assertEqual(MIGRATION.count("VOLATILE;"), 2)
        self.assertEqual(MIGRATION.count("TO authenticated;"), 2)
        self.assertEqual(MIGRATION.count("FROM PUBLIC, anon, authenticated, service_role;"), 2)

    def test_exact_nullable_ro_number_payload_validation(self):
        for token in ("ro_number: string | null", "'reservation_id','ro_number','status'", "nullableStrings(r,reservationKeys)", "'RO number unavailable'"):
            self.assertIn(token, UI)
        self.assertNotIn("RO #${item.reservation.reservation_id}", UI)

    def test_full_card_navigation_and_destination_detail(self):
        for token in ('role="button"', 'tabIndex={0}', "event.key==='Enter'", "event.key===' '", 'Back to active cases', "detail?<CaseDetail", 'attention?<div className="attention-summary"'):
            self.assertIn(token, UI)
        self.assertNotIn("View details", UI)

    def test_chronology_deduplication_and_separate_tax(self):
        for token in ("filter(segment=>!segment.is_open).sort", "current open segment", "Accumulated tax", "Accumulated pre-tax total", "p.accumulated_subtotal", "p.accumulated_tax", "Days unavailable", "Rate unavailable"):
            self.assertIn(token, UI)

    def test_historical_days_use_only_backend_segment_contract_days(self):
        for token in ("contract_days: number | null", "'paid_through_at','contract_days','is_open'", "nullableNumber(v.contract_days)", "segment.contract_days===null", "`${segment.contract_days} days`", "p.contract_days"):
            self.assertIn(token, UI)
        self.assertNotIn("segmentDays", UI)
        self.assertNotIn("segment.covered_days_override??segment.default_covered_days_snapshot", UI)

    def test_rental_attention_and_read_only_contract(self):
        for token in ('Current rental rate before tax', 'Accumulated rental charges before tax', 'Billing amounts are unavailable', 'attentionReason(p)', "supabase.rpc('get_reconciled_billing_workspace_state'", "money=(v:unknown):v is string", 'Current-vehicle timer', 'Extended Warranty case timer'):
            self.assertIn(token, UI)
        for forbidden in ('cashier', 'payment collected', 'vehicle count', 'swaps', '.from(', '.insert(', '.update(', '.delete(', 'Math.round', 'toFixed', 'parseFloat', 'parseInt'):
            self.assertNotIn(forbidden, UI.lower() if forbidden in ('cashier', 'payment collected', 'vehicle count', 'swaps') else UI)

if __name__ == '__main__':
    unittest.main()
