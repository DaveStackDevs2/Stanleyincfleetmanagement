import pathlib, unittest
ROOT=pathlib.Path(__file__).parents[1]
SQL=(ROOT/'supabase/migrations/20260806120000_authoritative_loaner_rental_tax.sql').read_text()
UI=(ROOT/'frontend/src/admin/PayTypeManagement.tsx').read_text()
class Phase4TaxContract(unittest.TestCase):
 def test_exact_contract(self):
  for token in ["billing.loaner_rental_tax_rate", "'0.10'::jsonb", "69.95", "6.995"]: self.assertIn(token,SQL)
  self.assertIn("p_taxable_base*v_rate",SQL)
  self.assertNotIn('round(',SQL.lower())
  self.assertIn("p_taxable_base",SQL)
 def test_exemptions_and_snapshots(self):
  self.assertIn("('GM Warranty', 'Extended Warranty')",SQL)
  for name in ('tax_rate_snapshot','is_taxable_snapshot','tax_rate_source_snapshot'): self.assertIn(name,SQL)
  self.assertIn('ck_pay_type_rules_only_warranty_tax_exempt',SQL)
 def test_security_and_mismatch(self):
  self.assertIn('Submitted tax amount does not match the authoritative calculation',SQL)
  self.assertIn("security invoker set search_path to ''",SQL.lower())
  self.assertIn("security definer set search_path to ''",SQL.lower())
  self.assertIn('from public,anon,authenticated',SQL.lower())
 def test_frontend_rpc_only_and_fixed_taxability(self):
  self.assertIn("supabase.rpc('get_admin_loaner_rental_tax_state')",UI)
  self.assertIn("supabase.rpc('set_admin_loaner_rental_tax_rate_state'",UI)
  self.assertNotIn("from('admin_settings')",UI)
  self.assertNotIn('checked={form.taxable}',UI)
  self.assertNotIn('checked={editForm.taxable}',UI)
  self.assertIn('percentageToDecimalFraction',UI)
  self.assertIn('await load()',UI)
if __name__=='__main__': unittest.main()
