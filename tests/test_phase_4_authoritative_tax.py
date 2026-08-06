import pathlib
import unittest
from decimal import Decimal

ROOT = pathlib.Path(__file__).parents[1]
SQL = (ROOT / 'supabase/migrations/20260806120000_authoritative_loaner_rental_tax.sql').read_text()
UI = (ROOT / 'frontend/src/admin/PayTypeManagement.tsx').read_text()


class Phase4TaxContract(unittest.TestCase):
    def test_exact_contract_and_no_rounding(self):
        for token in ["billing.loaner_rental_tax_rate", "'0.10'::jsonb", "69.95", "6.995"]:
            self.assertIn(token, SQL)
        self.assertEqual(Decimal('69.95') * Decimal('0.10'), Decimal('6.995'))
        self.assertIn('p_taxable_base*v_rate', SQL)
        self.assertNotIn('round(', SQL.lower())

    def test_getter_uses_exact_live_tax_percentage_contract(self):
        getter = SQL[SQL.index('create or replace function public.get_admin_loaner'):SQL.index('create or replace function public.set_admin_loaner')]
        self.assertIn("'status','admin_loaner_rental_tax_ready'", getter)
        self.assertIn("'tax_percentage',v_rate*100", getter)
        self.assertNotRegex(getter, r"'percentage'\s*,")
        self.assertIn('typeof value.tax_percentage', UI)
        self.assertNotIn('typeof value.percentage', UI)

    def test_setter_uses_exact_live_contract_and_frontend_validates_it(self):
        setter = SQL[SQL.index('create or replace function public.set_admin_loaner'):SQL.index('alter function public.get_admin_loaner')]
        for token in ["'admin_loaner_rental_tax_updated'", "'setting_key','billing.loaner_rental_tax_rate'", "'previous_tax_rate'", "'tax_rate',p_tax_rate", "'tax_percentage',p_tax_rate*100", "'exact_no_rounding'", "'separate_child_line'"]:
            self.assertIn(token, setter)
        self.assertNotIn('current_tax_rate', setter)
        self.assertIn('function parseTaxMutation', UI)
        self.assertIn('value.tax_rate !== expectedRate', UI)
        self.assertIn('value.tax_percentage !== expectedPercentage', UI)
        self.assertLess(UI.index('parseTaxMutation(result.data'), UI.index("if (await load())", UI.index("supabase.rpc('set_admin_loaner")))
        self.assertIn('The tax rate changed, but the authoritative state could not be reloaded', UI)

    def test_parent_live_payload_and_defensive_resolver_validation(self):
        parent = SQL[SQL.index('create or replace function public.create_billing_parent'):SQL.index('alter function public.create_billing_parent')]
        for token in ["'total_amount'", "'tax_explanation'", "Billing start time is required", "Billing tax resolution returned an invalid result", "v_tax->>'status' <> 'billing_tax_resolved'", "jsonb_typeof(v_tax->'tax_amount') <> 'number'", "jsonb_typeof(v_tax->'tax_rate') <> 'number'", "jsonb_typeof(v_tax->'is_taxable') <> 'boolean'", "is distinct from v_rule_id"]:
            self.assertIn(token, parent)
        self.assertNotRegex(parent, r"'total'\s*,")
        self.assertNotRegex(parent, r"'explanation'\s*,v_tax")

    def test_resolver_live_lookup_setting_and_security_contract(self):
        resolver = SQL[SQL.index('create or replace function public.resolve_billing'):SQL.index('create or replace function public.ensure_tax')]
        for token in ["v_pay_type text := btrim(p_pay_type)", "Pay type not found", "Pay type is inactive", "jsonb_typeof(setting_value) = 'number'", "'billing_tax_resolved'", "'pay_type_exemption'", "security invoker set search_path to ''", 'owner to postgres', 'from public, anon, authenticated', 'to service_role']:
            self.assertIn(token, resolver)

    def test_exemptions_snapshots_and_fixed_taxability(self):
        self.assertIn("('GM Warranty', 'Extended Warranty')", SQL)
        for name in ('tax_rate_snapshot', 'is_taxable_snapshot', 'tax_rate_source_snapshot'):
            self.assertIn(name, SQL)
        self.assertIn('ck_pay_type_rules_only_warranty_tax_exempt', SQL)
        self.assertNotIn('checked={form.taxable}', UI)
        self.assertNotIn('checked={editForm.taxable}', UI)
        self.assertIn('p_pay_type: form.payType.trim(), p_is_taxable: true', UI)
        self.assertIn('p_pay_type_rule_id: editForm.id, p_is_taxable: editForm.taxable', UI)

    def test_migration_is_narrow_and_create_argument_matches_live(self):
        self.assertNotIn('CREATE OR REPLACE FUNCTION public.get_admin_pay_type_rules_state', SQL)
        self.assertNotIn('CREATE OR REPLACE FUNCTION public.set_admin_pay_type_rule_enabled_state', SQL)
        self.assertNotRegex(SQL, r'(?:revoke|grant execute).*get_admin_pay_type_rules_state')
        self.assertNotRegex(SQL, r'(?:revoke|grant execute).*set_admin_pay_type_rule_enabled_state')
        create_call = UI[UI.index("supabase.rpc('create_admin_pay_type_rule_state'"):UI.index('}),', UI.index("supabase.rpc('create_admin_pay_type_rule_state'"))]
        self.assertIn('p_default_daily_amount: amount', create_call)
        self.assertNotIn('p_default_daily_rate', create_call)


    def test_unrestricted_snapshot_precision_and_nullable_tax_chains(self):
        self.assertIn('tax_rate_snapshot numeric;', SQL)
        self.assertIn(
            'alter column tax_rate_snapshot type numeric using tax_rate_snapshot::numeric',
            SQL,
        )
        self.assertNotIn('tax_rate_snapshot numeric(7,6)', SQL)

        nullable_parameters = (
            'p_tax_amount numeric DEFAULT NULL::numeric',
            'p_billing_tax_amount numeric DEFAULT NULL::numeric',
            'p_extension_tax_amount numeric DEFAULT NULL::numeric',
        )
        for parameter in nullable_parameters:
            self.assertIn(parameter, SQL)

        zero_coercions = (
            'coalesce(p_tax_amount, 0)',
            'coalesce(p_billing_tax_amount, 0)',
            'coalesce(p_extension_tax_amount, 0)',
        )
        for coercion in zero_coercions:
            self.assertNotIn(coercion, SQL.lower())

        for function_name in (
            'create_transportation_event_billing_line_state',
            'create_reservation_billing_line_state',
            'activate_case_billing_state',
            'create_start_and_bill_case_with_vehicle_by_vin_state',
            'create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_',
            'create_start_bill_case_and_get_payload_state',
            'create_extension_billing_line_state',
            'accept_extension_commit_state',
            'accept_reservation_extension_state',
            'accept_case_extension_and_get_unified_payload_state',
            'accept_transportation_event_extension_state',
        ):
            self.assertIn(f'function public.{function_name}', SQL.lower())


if __name__ == '__main__':
    unittest.main()
