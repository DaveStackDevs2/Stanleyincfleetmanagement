import pathlib
import re
import unittest
from decimal import Decimal

ROOT = pathlib.Path(__file__).parents[1]
MIGRATION = ROOT / 'supabase/migrations/20260806130000_admin_pay_type_taxability_source_of_truth.sql'
SQL = MIGRATION.read_text()
NORMALIZED = re.sub(r'\s+', ' ', SQL).lower()
PHASE4 = (ROOT / 'supabase/migrations/20260806120000_authoritative_loaner_rental_tax.sql').read_text()
UI = (ROOT / 'frontend/src/admin/PayTypeManagement.tsx').read_text()


class PayTypeTaxabilityCorrection(unittest.TestCase):
    def normalized_function(self, name, following):
        lower = SQL.lower()
        start = lower.index(f'function public.{name}')
        end = lower.index(following, start)
        return re.sub(r'\s+', ' ', lower[start:end])

    def test_follow_up_order_and_no_data_rewrite_or_name_rule(self):
        self.assertGreater(MIGRATION.name, '20260806120000_authoritative_loaner_rental_tax.sql')
        prefix = NORMALIZED[:NORMALIZED.index('create or replace function public.resolve_billing_tax_state')]
        self.assertNotRegex(prefix, r'\b(?:insert|update|delete)\s+(?:into\s+|from\s+)?public\.pay_type_rules')
        self.assertNotIn('gm warranty', NORMALIZED)
        self.assertNotIn('extended warranty', NORMALIZED)
        self.assertNotIn('pay_type not in', NORMALIZED)

    def test_synchronization_constraint_replaces_name_lock(self):
        self.assertIn('drop constraint if exists ck_pay_type_rules_only_warranty_tax_exempt', NORMALIZED)
        self.assertIn('add constraint ck_pay_type_rules_tax_fields_synchronized', NORMALIZED)
        self.assertRegex(NORMALIZED, r'check\s*\(tax_applicable\s*=\s*is_taxable\)')

    def test_resolver_uses_verified_stored_taxability_contract(self):
        resolver = self.normalized_function(
            'resolve_billing_tax_state',
            'alter function public.resolve_billing_tax_state',
        )
        guard = (
            'if v_rule.is_taxable is null or '
            'v_rule.tax_applicable is distinct from v_rule.is_taxable then'
        )
        assignment = 'v_is_taxable := v_rule.is_taxable;'
        self.assertIn(guard, resolver)
        self.assertLess(resolver.index(guard), resolver.index(assignment))
        self.assertIn("raise exception 'pay-type tax configuration is invalid'", resolver)
        self.assertIn("'pay_type_exemption'", resolver)
        self.assertIn('v_tax_amount := p_taxable_base * v_tax_rate;', resolver)
        self.assertNotIn('round(', resolver)
        self.assertEqual(Decimal('69.95') * Decimal('0.10'), Decimal('6.995'))

    def test_create_and_update_store_submitted_boolean_in_both_fields(self):
        create = self.normalized_function(
            'create_admin_pay_type_rule_state',
            'alter function public.create_admin_pay_type_rule_state',
        )
        update = self.normalized_function(
            'update_admin_pay_type_rule_state',
            'alter function public.update_admin_pay_type_rule_state',
        )
        self.assertIn('if p_is_taxable is null then', create)
        self.assertIn('if p_is_taxable is null then', update)
        self.assertRegex(
            create,
            r'values\s*\(\s*btrim\(p_pay_type\),\s*p_is_taxable,\s*true,\s*true,\s*p_is_taxable,',
        )
        locked_select = (
            'select rule.* into v_rule from public.pay_type_rules rule '
            'where rule.id = p_pay_type_rule_id for update;'
        )
        missing_row = "if not found then raise exception 'pay type rule not found'"
        mutation = 'update public.pay_type_rules set is_taxable = p_is_taxable, tax_applicable = p_is_taxable,'
        self.assertIn(locked_select, update)
        self.assertIn(missing_row, update)
        self.assertIn(mutation, update)
        self.assertLess(update.index(locked_select), update.index(missing_row))
        self.assertLess(update.index(missing_row), update.index(mutation))

    def test_exact_security_and_grant_boundaries(self):
        resolver = self.normalized_function(
            'resolve_billing_tax_state',
            'alter function public.resolve_billing_tax_state',
        )
        create = self.normalized_function(
            'create_admin_pay_type_rule_state',
            'alter function public.create_admin_pay_type_rule_state',
        )
        update = self.normalized_function(
            'update_admin_pay_type_rule_state',
            'alter function public.update_admin_pay_type_rule_state',
        )
        self.assertIn("language plpgsql set search_path to ''", resolver)
        self.assertNotIn('security definer', resolver)
        for admin in (create, update):
            self.assertIn('language plpgsql security definer', admin)
            self.assertIn("set search_path to ''", admin)
        self.assertIn(
            'revoke all on function public.resolve_billing_tax_state(text,numeric) '
            'from public, anon, authenticated, service_role',
            NORMALIZED,
        )
        self.assertIn(
            'grant execute on function public.resolve_billing_tax_state(text,numeric) to service_role',
            NORMALIZED,
        )
        for signature in (
            'create_admin_pay_type_rule_state(text,boolean,numeric,integer,text)',
            'update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text)',
        ):
            self.assertIn(f'alter function public.{signature} owner to postgres', NORMALIZED)
            self.assertIn(
                f'revoke all on function public.{signature} from public, anon, authenticated, service_role',
                NORMALIZED,
            )
            self.assertIn(
                f'grant execute on function public.{signature} to authenticated, service_role',
                NORMALIZED,
            )

    def test_add_and_edit_expose_and_submit_taxable(self):
        self.assertIn('checked={form.taxable}', UI)
        self.assertIn('checked={editForm.taxable}', UI)
        self.assertIn('p_is_taxable: form.taxable', UI)
        self.assertIn('p_is_taxable: editForm.taxable', UI)
        self.assertIn('p_default_daily_amount: amount', UI)
        update_start = UI.index("supabase.rpc('update_admin_pay_type_rule_state'")
        update_call = UI[update_start:UI.index('})', update_start)]
        self.assertNotIn('p_default_daily_rate: amount', update_call)
        self.assertIn('readOnly aria-readonly="true"', UI)
        self.assertNotRegex(UI, r'(?:delete|remove)_admin_pay_type')
        self.assertIn('set_admin_pay_type_rule_enabled_state', UI)
        self.assertIn('Save Colors', UI)

    def test_existing_exact_snapshots_and_null_propagation_remain(self):
        for token in (
            'tax_rate_snapshot numeric;',
            'is_taxable_snapshot',
            'tax_rate_source_snapshot',
            'p_taxable_base*v_rate',
            'ensure_tax_child_line_state',
        ):
            self.assertIn(token, PHASE4)
        self.assertNotIn('round(', PHASE4.lower())
        for parameter in (
            'p_tax_amount numeric DEFAULT NULL::numeric',
            'p_billing_tax_amount numeric DEFAULT NULL::numeric',
            'p_extension_tax_amount numeric DEFAULT NULL::numeric',
        ):
            self.assertIn(parameter, PHASE4)
        for coercion in (
            'coalesce(p_tax_amount, 0)',
            'coalesce(p_billing_tax_amount, 0)',
            'coalesce(p_extension_tax_amount, 0)',
        ):
            self.assertNotIn(coercion, PHASE4.lower())
        self.assertIn("'0.10'::jsonb", PHASE4)
        self.assertIn('grant execute on function public.create_billing_parent_line_state', PHASE4)


if __name__ == '__main__':
    unittest.main()
