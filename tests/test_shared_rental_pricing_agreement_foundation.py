import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/migrations/20260812120000_verified_shared_rental_pricing_agreement_foundation.sql'
SQL=MIGRATION.read_text(); LOWER=SQL.lower()

class SharedPricingAgreementContractTests(unittest.TestCase):
 def test_migration_is_ordered_idempotent_and_data_free(self):
  self.assertGreater(MIGRATION.name,'20260811120000_verified_pay_type_independent_rental_rate_cards.sql')
  for token in ('create table if not exists','add column if not exists','drop constraint if exists','create unique index if not exists','drop trigger if exists','on conflict'):
   self.assertIn(token,LOWER)
  schema_section=LOWER.split('create or replace function public.create_admin_rental_rate_card_state',1)[0]
  self.assertNotRegex(schema_section,r"insert into public\.(quotes|reservations|transportation_events|rental_pricing_agreements|billing_lines|customers|vehicles)")
 def test_table_constraints_indexes_and_rls(self):
  for value in ('origin_type text not null','transportation_event_id uuid not null','daily_rate_snapshot numeric(12,2) not null',"origin_type in ('quote','reservation','walk_in')",'ck_rental_pricing_agreements_plan_snapshots','ck_rental_pricing_agreements_origin_linkage','enable row level security'):
   self.assertIn(value,LOWER)
  for index in ('ux_rental_pricing_agreements_quote_id','ux_rental_pricing_agreements_reservation_id','ux_rental_pricing_agreements_transportation_event_id'):
   self.assertIn(index,LOWER)
 def test_permission_and_function_security(self):
  self.assertIn("'billing.pricing_agreement_manage'",LOWER); self.assertIn("r.role_name='dev'",LOWER)
  for sig in ('create_quote_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text)','create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text)','convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text)','create_walk_in_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text)'):
   self.assertIn(sig,LOWER)
  self.assertGreaterEqual(LOWER.count("security definer set search_path to ''"),5)
  self.assertGreaterEqual(LOWER.count("auth.jwt()->>'aal'"),4)
 def test_event_continuity_and_no_premature_engines(self):
  conversion=LOWER.split('create or replace function public.convert_quote_to_reservation_with_pricing_agreement_state',1)[1].split('end;$function$;',1)[0]
  self.assertIn('for update',conversion); self.assertIn(",status,reservation_type,",conversion.replace(' ','')); self.assertIn(",'quote',v_quote.reservation_type",conversion.replace(' ','')); self.assertIn("status='converted'",conversion)
  self.assertNotIn('create_transportation_event_state',conversion)
  for forbidden in ('start_vehicle_use_state','contract_periods','insert into public.billing_lines','pricing_started_at='):
   self.assertNotIn(forbidden,conversion)
 def test_billing_audit_and_privilege_contracts(self):
  for value in ('ck_billing_lines_pricing_snapshot_all_or_none','ix_billing_lines_pricing_agreement_id','audit_rental_pricing_agreement_state','quote_conversion','pricing_activation','plan_change','material_update'):
   self.assertIn(value,LOWER)
  self.assertIn('revoke insert,update,delete,truncate,references,trigger on table public.audit_log',LOWER)
  for table in ('transportation_events','reservations','vehicle_events','contract_periods','billing_lines'):
   self.assertRegex(LOWER,rf'revoke truncate,references,trigger on table [^;]*public\.{table}')
 def test_monthly_fallback_and_frontend_validation(self):
  self.assertIn('ck_rental_rate_rules_monthly_requires_weekly',LOWER)
  message='Weekly rate is required when a monthly rate is configured'
  self.assertGreaterEqual(SQL.count(message),2)
  frontend=(ROOT/'frontend/src/admin/PayTypeManagement.tsx').read_text()
  self.assertIn(message,frontend); self.assertIn('monthlyRate !== null && weeklyRate === null',frontend)

if __name__=='__main__': unittest.main()
