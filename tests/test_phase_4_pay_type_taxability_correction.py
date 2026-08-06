import pathlib
import re
import unittest
from decimal import Decimal

ROOT = pathlib.Path(__file__).parents[1]
MIGRATION = ROOT / 'supabase/migrations/20260806130000_admin_pay_type_taxability_source_of_truth.sql'
SQL = MIGRATION.read_text()
PHASE4 = (ROOT / 'supabase/migrations/20260806120000_authoritative_loaner_rental_tax.sql').read_text()
UI = (ROOT / 'frontend/src/admin/PayTypeManagement.tsx').read_text()


class PayTypeTaxabilityCorrection(unittest.TestCase):
    def function(self, name, following):
        return SQL[SQL.index(f'function public.{name}'):SQL.index(following, SQL.index(f'function public.{name}'))]

    def test_follow_up_order_and_no_data_rewrite_or_name_rule(self):
        self.assertGreater(MIGRATION.name, '20260806120000_authoritative_loaner_rental_tax.sql')
        prefix = SQL[:SQL.index('create or replace function public.resolve_billing_tax_state')]
        self.assertNotRegex(prefix.lower(), r'\b(?:insert|update|delete)\s+(?:into\s+|from\s+)?public\.pay_type_rules')
        self.assertNotIn('GM Warranty', SQL)
        self.assertNotIn('Extended Warranty', SQL)
        self.assertNotIn("pay_type not in", SQL.lower())

    def test_synchronization_constraint_replaces_name_lock(self):
        self.assertIn('drop constraint if exists ck_pay_type_rules_only_warranty_tax_exempt', SQL)
        self.assertIn('add constraint ck_pay_type_rules_tax_fields_synchronized', SQL)
        self.assertRegex(SQL, r'check\s*\(tax_applicable\s*=\s*is_taxable\)')

    def test_resolver_uses_stored_value_and_preserves_exact_contract(self):
        resolver = self.function('resolve_billing_tax_state', 'alter function public.resolve_billing_tax_state')
        synchronized_guard = (
            'if v_rule.is_taxable is null or '
            'v_rule.tax_applicable is distinct from v_rule.is_taxable then'
        )
        self.assertIn(synchronized_guard, resolver)
        self.assertLess(resolver.index(synchronized_guard), resolver.index('v_taxable := v_rule.is_taxable'))
        self.assertIn("raise exception 'Pay type tax configuration is invalid' using errcode='22023'", resolver)
        self.assertIn('v_taxable := v_rule.is_taxable', resolver)
        self.assertIn("exception when others then raise exception 'Loaner and rental tax rate is invalid' using errcode='22023'", resolver)
        self.assertIn('p_taxable_base*v_rate', resolver)
        self.assertNotIn('round(', resolver.lower())
        self.assertIn("'pay_type_exemption'", resolver)
        self.assertEqual(Decimal('69.95') * Decimal('0.10'), Decimal('6.995'))

    def test_create_and_update_store_submitted_boolean_in_both_fields(self):
        create = self.function('create_admin_pay_type_rule_state', 'create or replace function public.update_admin')
        update = self.function('update_admin_pay_type_rule_state', 'alter function public.create_admin')
        self.assertRegex(create, r'values\(btrim\(p_pay_type\),p_is_taxable,true,true,p_is_taxable,')
        self.assertIn('is_taxable=p_is_taxable,tax_applicable=p_is_taxable', update)
        self.assertIn('p_is_taxable is null', create)
        self.assertIn('p_is_taxable is null', update)
        locked_select = 'select * into v_rule from public.pay_type_rules where id=p_pay_type_rule_id for update;'
        missing_row = "if not found then raise exception 'Pay type rule not found' using errcode='P0002'; end if;"
        mutation = 'update public.pay_type_rules set is_taxable=p_is_taxable,tax_applicable=p_is_taxable'
        self.assertEqual(update.count(locked_select), 1)
        self.assertEqual(update.count(missing_row), 1)
        self.assertLess(update.index(locked_select), update.index(missing_row))
        self.assertLess(update.index(missing_row), update.index(mutation))

    def test_exact_security_contracts(self):
        self.assertIn("language plpgsql security invoker set search_path to ''", SQL)
        self.assertEqual(SQL.count("language plpgsql security definer set search_path to ''"), 2)
        for signature in ('resolve_billing_tax_state(text,numeric)', 'create_admin_pay_type_rule_state(text,boolean,numeric,integer,text)', 'update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text)'):
            self.assertIn(f'alter function public.{signature} owner to postgres', SQL)
        self.assertIn('resolve_billing_tax_state(text,numeric) from public, anon, authenticated', SQL)
        self.assertIn('resolve_billing_tax_state(text,numeric) to service_role', SQL)
        for signature in ('create_admin_pay_type_rule_state(text,boolean,numeric,integer,text)', 'update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text)'):
            self.assertIn(f'{signature} from public,anon,authenticated', SQL)
            self.assertIn(f'{signature} to authenticated,service_role', SQL)

    def test_add_and_edit_expose_and_submit_taxable(self):
        self.assertIn('checked={form.taxable}', UI)
        self.assertIn('checked={editForm.taxable}', UI)
        self.assertIn('p_is_taxable: form.taxable', UI)
        self.assertIn('p_is_taxable: editForm.taxable', UI)
        self.assertIn('p_default_daily_amount: amount', UI)
        update_call = UI[UI.index("supabase.rpc('update_admin_pay_type_rule_state'"):UI.index('})', UI.index("supabase.rpc('update_admin_pay_type_rule_state'"))]
        self.assertNotIn('p_default_daily_rate: amount', update_call)
        self.assertIn('readOnly aria-readonly="true"', UI)
        self.assertNotRegex(UI, r"(?:delete|remove)_admin_pay_type")
        self.assertIn("set_admin_pay_type_rule_enabled_state", UI)
        self.assertIn('Save Colors', UI)

    def test_existing_exact_snapshots_grants_and_null_propagation_remain(self):
        for token in ('tax_rate_snapshot numeric;', 'is_taxable_snapshot', 'tax_rate_source_snapshot', 'p_taxable_base*v_rate', 'ensure_tax_child_line_state'):
            self.assertIn(token, PHASE4)
        self.assertNotIn('round(', PHASE4.lower())
        for parameter in ('p_tax_amount numeric DEFAULT NULL::numeric', 'p_billing_tax_amount numeric DEFAULT NULL::numeric', 'p_extension_tax_amount numeric DEFAULT NULL::numeric'):
            self.assertIn(parameter, PHASE4)
        for coercion in ('coalesce(p_tax_amount, 0)', 'coalesce(p_billing_tax_amount, 0)', 'coalesce(p_extension_tax_amount, 0)'):
            self.assertNotIn(coercion, PHASE4.lower())
        self.assertIn("'0.10'::jsonb", PHASE4)
        self.assertIn('grant execute on function public.create_billing_parent_line_state', PHASE4)


if __name__ == '__main__':
    unittest.main()
