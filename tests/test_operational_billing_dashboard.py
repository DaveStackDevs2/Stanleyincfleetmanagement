import pathlib
import unittest

ROOT = pathlib.Path(__file__).parents[1]
SQL = (ROOT / 'supabase/migrations/20260807120000_operational_billing_dashboard.sql').read_text()
UI = (ROOT / 'frontend/src/billing/BillingWorkspace.tsx').read_text()
APP = (ROOT / 'frontend/src/App.tsx').read_text()


class OperationalBillingDashboardContract(unittest.TestCase):
    def test_rpc_security_boundary(self):
        statements = (
            'alter function public.get_billing_preview_state(uuid,timestamptz) owner to postgres;',
            'alter function public.get_billing_workspace_state(timestamptz) owner to postgres;',
            'revoke all on function public.get_billing_preview_state(uuid,timestamptz) from public, anon, authenticated, service_role;',
            'revoke all on function public.get_billing_workspace_state(timestamptz) from public, anon, authenticated, service_role;',
            'grant execute on function public.get_billing_preview_state(uuid,timestamptz) to authenticated;',
            'grant execute on function public.get_billing_workspace_state(timestamptz) to authenticated;',
        )
        self.assertEqual(SQL.rstrip().splitlines()[-6:], list(statements))
        self.assertNotIn('\nstable\n', SQL.lower())
        self.assertIn("errcode = '42501'", SQL)

    def test_live_frontend_hierarchy(self):
        for token in ('itemKeys', 'reservationKeys', 'currentVehicleKeys', 'readyKeys',
                      'segmentKeys', 'warrantyKeys', 'current_vehicle_contract_day',
                      'effective_covered_days', 'requires_manual_review', 'can_override'):
            self.assertIn(token, UI)
        for reconstructed in ('current_segment', 'contract_period:', 'historical_segments',
                              'missing_dependencies'):
            self.assertNotIn(reconstructed, UI)
        self.assertIn("missing_dependency?: string", UI)
        self.assertIn("extended_warranty: ExtendedWarranty | null", UI)

    def test_rpc_only_exact_string_display(self):
        self.assertIn("supabase.rpc('get_billing_workspace_state'", UI)
        for write in ('.from(', 'insert(', 'update(', 'delete('):
            self.assertNotIn(write, UI)
        for arithmetic in ('Math.round', 'toFixed', 'parseFloat', 'parseInt'):
            self.assertNotIn(arithmetic, UI)
        self.assertIn('money(', UI)

    def test_dashboard_wiring_preserved(self):
        self.assertIn("useState<Page>('dashboard')", APP)
        self.assertIn("onClick={() => setPage('dashboard')}", APP)
        self.assertIn('<BillingWorkspace />', APP)


if __name__ == '__main__':
    unittest.main()
