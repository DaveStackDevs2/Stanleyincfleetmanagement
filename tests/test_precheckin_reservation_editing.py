import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/20260818192000_verified_precheckin_reservation_editing.sql').read_text().lower()
UI=(ROOT/'frontend/src/reservations/ReservationsWorkspace.tsx').read_text()
EDIT=(ROOT/'frontend/src/reservations/EditReservationWorkspace.tsx').read_text()
class PrecheckinReservationEditingTests(unittest.TestCase):
 def test_security_and_guards(self):
  for value in ("security definer set search_path to ''",'auth.uid()','auth.jwt()',"'aal2'",'billing.pricing_agreement_manage','pricing_started_at','v_current_vehicle_continuity','billing_lines','for update'):self.assertIn(value,SQL)
 def test_narrow_write_and_expected_return_engine(self):
  update=re.search(r'update public\.reservations set (.*?) where id=',SQL,re.S).group(1)
  for field in ('start_date','expected_return_datetime','service_advisor','ro_number','notes'):self.assertIn(field,update)
  for field in ('vehicle_id','reservation_type','requested_model','pay_type'):self.assertNotIn(field,update)
  self.assertIn('public.set_expected_return_state(',SQL);self.assertIn("'expected_return_updated'",SQL)
  self.assertNotRegex(SQL,r'update public\.transportation_events set[^;]*expected_return_at')
  self.assertRegex(SQL,r'update public\.transportation_events set notes=v_notes,updated_at=v_at')
 def test_audit_and_no_side_effects_or_fixtures(self):
  self.assertIn('insert into public.audit_log',SQL)
  for field in ('scheduled_start','scheduled_return','service_advisor','ro_number','notes'):self.assertIn("'"+field+"'",SQL)
  for forbidden in ('test-stock','test-vin','1e6be455','insert into public.billing_lines','update public.rental_pricing_agreements','update public.vehicles'):self.assertNotIn(forbidden,SQL)
 def test_pickup_read_is_preserved_and_has_notes(self):
  read=SQL.split('create or replace function public.get_pricing_agreement_pickup_state',1)[1]
  for value in ("security definer set search_path to ''",'auth.jwt()',"'aal2'",'billing.pricing_agreement_manage',"'notes',r.notes",'vehicle_candidates'):self.assertIn(value,read)
 def test_frontend_authoritative_boundary(self):
  self.assertIn('Edit Reservation',UI)
  self.assertIn("supabase.rpc('get_pricing_agreement_pickup_state'",EDIT);self.assertIn("supabase.rpc('update_precheckin_reservation_state'",EDIT)
  for forbidden in ('.from(','set_expected_return_state','daily_rate *','weekly_rate *','monthly_rate *'):self.assertNotIn(forbidden,EDIT)
  for editable in ('Scheduled start','Scheduled return','Service advisor','RO number','Notes'):self.assertIn(editable,EDIT)
  self.assertIn('else if(await load())setResult(payload)',EDIT);self.assertIn('isoToDatetimeLocal',EDIT)
if __name__=='__main__':unittest.main()
