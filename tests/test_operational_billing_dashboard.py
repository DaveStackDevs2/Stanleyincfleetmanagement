import pathlib, unittest
ROOT=pathlib.Path(__file__).parents[1]
SQL=(ROOT/'supabase/migrations/20260807120000_operational_billing_dashboard.sql').read_text()
UI=(ROOT/'frontend/src/billing/BillingWorkspace.tsx').read_text()
APP=(ROOT/'frontend/src/App.tsx').read_text()
class OperationalBillingDashboardContract(unittest.TestCase):
 def test_rpc_security_boundary(self):
  for name in ('get_billing_preview_state(uuid,timestamptz)','get_billing_workspace_state(timestamptz)'):
   self.assertIn(f'alter function public.{name} owner to postgres',SQL); self.assertIn(f'revoke all on function public.{name} from public, anon, authenticated, service_role',SQL); self.assertIn(f'grant execute on function public.{name} to authenticated',SQL)
  self.assertGreaterEqual(SQL.count("auth.jwt()->>'aal'"),2); self.assertGreaterEqual(SQL.count('auth_user_id=auth.uid()'),2); self.assertGreaterEqual(SQL.count('security definer'),2); self.assertGreaterEqual(SQL.count("set search_path to ''"),2)
 def test_preview_authoritative_contract(self):
  for token in ('public.business_contract_days','daily_rate_override','default_daily_rate_snapshot','public.resolve_rental_daily_rate_state','default_daily_amount','public.resolve_billing_tax_state','tax_rate_snapshot','historical_segments','extended_warranty',"'billing_preview_missing_dependency'","'billing_preview_missing_configuration'","'billing_preview_ready'"): self.assertIn(token,SQL)
  self.assertIn('v_subtotal:=v_days*v_rate',SQL); self.assertNotIn('round(',SQL.lower())
 def test_workspace_empty_and_sanitized(self):
  self.assertIn("v_items jsonb:='[]'",SQL); self.assertIn("'billing_workspace_ready'",SQL); self.assertIn("'billing_preview_unavailable'",SQL); self.assertNotIn('sqlerrm',SQL.lower())
 def test_dashboard_and_rpc_only_read(self):
  self.assertIn("useState<Page>('dashboard')",APP); self.assertIn("onClick={() => setPage('dashboard')}",APP); self.assertIn('<BillingWorkspace />',APP)
  self.assertIn("supabase.rpc('get_billing_workspace_state'",UI); self.assertNotIn('.from(',UI); self.assertNotIn('insert(',UI); self.assertNotIn('update(',UI); self.assertNotIn('delete(',UI)
 def test_complete_validation_exact_strings_no_calculation(self):
  for token in ('exactKeys','parseWorkspace','parseReady','parseSegment','exactMoney','attention_count as number)!==value.case_count'): self.assertIn(token,UI)
  for forbidden in ('Math.round','toFixed','parseFloat','parseInt') : self.assertNotIn(forbidden,UI)
  self.assertIn('Refresh',UI); self.assertNotIn('Start billing',UI); self.assertNotIn('Collect payment',UI)
if __name__=='__main__': unittest.main()
