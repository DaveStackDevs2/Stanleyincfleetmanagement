import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/migrations/20260811120000_verified_pay_type_independent_rental_rate_cards.sql'
SQL = MIGRATION.read_text()
LOWER = re.sub(r'\s+', ' ', SQL.lower())
UI = (ROOT / 'frontend/src/admin/PayTypeManagement.tsx').read_text()

class RentalRateCardCheckpointTests(unittest.TestCase):
    def test_schema_is_data_free_and_legacy_compatible(self):
        prefix = LOWER.split('create or replace function', 1)[0]
        self.assertNotRegex(prefix, r'\b(?:insert|update|delete)\s+(?:into\s+|from\s+)?public\.rental_rate_rules')
        self.assertIn('alter column pay_type_rule_id drop not null', LOWER)
        self.assertIn('weekly_rate numeric(12,2)', LOWER)
        self.assertIn('monthly_rate numeric(12,2)', LOWER)
        self.assertIn('drop index if exists public.ux_rental_rate_rules_current_class_pay_type', LOWER)
        self.assertIn('create unique index if not exists ux_rental_rate_rules_current_class on public.rental_rate_rules (lower(btrim(vehicle_class))) where is_active = true and effective_to is null', LOWER)
        self.assertNotIn('drop constraint rental_rate_rules_pay_type_rule_id_fkey', LOWER)
        self.assertNotIn('drop index if exists public.ix_rental_rate_rules_pay_type_rule_id', LOWER)

    def test_exact_rpc_security_and_contract(self):
        signatures = ['resolve_rental_rate_card_state(text,timestamptz)', 'get_admin_rental_rate_cards_state()',
          'create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer)',
          'update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer)',
          'set_admin_rental_rate_card_enabled_state(uuid,boolean)']
        for signature in signatures:
            self.assertIn(f'alter function public.{signature} owner to postgres', LOWER)
        self.assertIn("stable security invoker set search_path to ''", LOWER)
        self.assertIn("permission_key='user_admin.manage'", LOWER)
        self.assertIn("interval '1 microsecond'", LOWER)
        self.assertIn("when effective_to is not null then effective_to", LOWER)
        self.assertIn("when p_is_enabled and not is_active then v_at", LOWER)
        self.assertIn("'rental_rate_card_not_configured'", LOWER)
        for field in ['daily_rate','weekly_rate','monthly_rate','effective_from','effective_to','vehicle_class','rental_rate_rule_id']:
            self.assertIn(field, LOWER)

    def test_frontend_uses_only_new_rate_card_admin_rpcs(self):
        for rpc in ['get_admin_rental_rate_cards_state','create_admin_rental_rate_card_state','update_admin_rental_rate_card_state','set_admin_rental_rate_card_enabled_state']:
            self.assertIn(f"supabase.rpc('{rpc}'", UI)
        for rpc in ['get_admin_rental_rate_rules_state','create_admin_rental_rate_rule_state','update_admin_rental_rate_rule_state','set_admin_rental_rate_rule_enabled_state']:
            self.assertNotIn(f"supabase.rpc('{rpc}'", UI)
        self.assertIn('Weekly rate (optional)', UI)
        self.assertIn('Monthly rate (optional)', UI)
        self.assertNotIn('<th>Pay type</th><th>Daily rate</th>', UI)
        self.assertNotIn('p_pay_type_rule_id:rateForm', UI)
        self.assertIn('Cancel / Return to Rates, Fees &amp; Billing Rules', UI)

if __name__ == '__main__': unittest.main()
