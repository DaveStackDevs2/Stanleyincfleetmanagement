import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/20260818192000_verified_precheckin_reservation_editing.sql').read_text().lower()
UI=(ROOT/'frontend/src/reservations/ReservationsWorkspace.tsx').read_text()
EDIT=(ROOT/'frontend/src/reservations/EditReservationWorkspace.tsx').read_text()
class PrecheckinReservationEditingTests(unittest.TestCase):
 def test_security_and_guards(self):
  for value in ("security definer set search_path to ''",'auth.uid()','auth.jwt()',"'aal2'",'billing.pricing_agreement_manage','pricing_started_at','v_current_vehicle_continuity','v_current_open_billing_lines','for update'):self.assertIn(value,SQL)
  signature=SQL.split('returns jsonb',1)[0]
  for argument in ('p_service_advisor text default null','p_ro_number text default null','p_notes text default null'):self.assertIn(argument,signature)
  self.assertRegex(SQL,r'from public\.transportation_events where id=v_reservation\.transportation_event_id for update;')
  self.assertIn("if v_reservation.status='cancelled' or v_reservation.actual_return_datetime is not null",SQL)
  self.assertNotIn("in ('cancelled','returned')",SQL)
  self.assertRegex(SQL,r"lower\(btrim\(v_event\.status\)\)<>'active' or v_event\.closed_at is not null then raise exception 'reservation transportation event is not active' using errcode='p0001'")
  self.assertNotRegex(SQL,r'from public\.billing_lines bl where bl\.transportation_event_id')
 def test_narrow_write_and_expected_return_engine(self):
  update=re.search(r'update public\.reservations set (.*?) where id=',SQL,re.S).group(1)
  for field in ('start_date','expected_return_datetime','service_advisor','ro_number','notes'):self.assertIn(field,update)
  for field in ('vehicle_id','reservation_type','requested_model','pay_type'):self.assertNotIn(field,update)
  self.assertIn('public.set_expected_return_state(',SQL);self.assertIn("'expected_return_updated'",SQL)
  self.assertNotRegex(SQL,r'update public\.transportation_events set[^;]*expected_return_at')
  self.assertRegex(SQL,r'update public\.transportation_events set notes=v_notes,updated_at=v_at')
  self.assertRegex(SQL,r'update public\.reservations set .*? returning \* into v_reservation;',re.S)
  self.assertRegex(SQL,r'update public\.transportation_events set notes=v_notes,updated_at=v_at .*? returning \* into v_event;')
  audit_loop_end=SQL.index('end loop;',SQL.index('foreach v_field'))
  self.assertGreater(SQL.index('update public.reservations set'),audit_loop_end)
  self.assertGreater(SQL.index('v_expected:=public.set_expected_return_state'),audit_loop_end)
  self.assertGreater(SQL.index('update public.transportation_events set notes='),audit_loop_end)
 def test_audit_and_no_side_effects_or_fixtures(self):
  self.assertIn('insert into public.audit_log',SQL)
  for field in ('scheduled_start','scheduled_return','service_advisor','ro_number','notes'):self.assertIn("'"+field+"'",SQL)
  self.assertIn("'changed_fields',v_changed_fields",SQL)
  self.assertNotIn("'changed_fields',to_jsonb",SQL)
  reservation_json=re.search(r"'reservation',jsonb_build_object\((.*?)\),\s*'transportation_event'",SQL,re.S).group(1)
  for field in ('v_reservation.start_date','v_reservation.expected_return_datetime','v_reservation.service_advisor','v_reservation.ro_number','v_reservation.notes'):self.assertIn(field,reservation_json)
  for stale in ('p_start_date','p_expected_return_datetime','v_advisor','v_ro','v_notes'):self.assertNotIn(stale,reservation_json)
  event_json=re.search(r"'transportation_event',jsonb_build_object\((.*?)\)\);",SQL,re.S).group(1)
  for field in ('v_event.expected_return_at','v_event.notes'):self.assertIn(field,event_json)
  for stale in ('p_expected_return_datetime','v_notes'):self.assertNotIn(stale,event_json)
  for forbidden in ('test-stock','test-vin','1e6be455','insert into public.billing_lines','update public.rental_pricing_agreements','update public.vehicles'):self.assertNotIn(forbidden,SQL)
 def test_pickup_read_is_preserved_and_has_notes(self):
  read=SQL.split('create or replace function public.get_pricing_agreement_pickup_state',1)[1]
  for value in ("security definer set search_path to ''",'auth.jwt()',"'aal2'",'billing.pricing_agreement_manage',"'notes',r.notes",'vehicle_candidates'):self.assertIn(value,read)
  self.assertIn("case vc.candidate_state when 'ready' then 1 when 'pending_return' then 2 else 3 end",read)
  self.assertIn('join public.rental_pricing_agreements a on a.reservation_id=r.id and a.transportation_event_id=r.transportation_event_id and a.is_active=true\n',read)
  self.assertNotRegex(read,r'join public\.rental_pricing_agreements[^\n]*pricing_started_at')
  self.assertIn("join public.transportation_events te on te.id=r.transportation_event_id and te.status='active'",read)
  self.assertIn("where r.status is distinct from 'cancelled' and r.actual_return_datetime is null and a.pricing_started_at is null",read)
 def test_frontend_authoritative_boundary(self):
  self.assertIn('Edit Reservation',UI)
  self.assertIn("supabase.rpc('get_pricing_agreement_pickup_state'",EDIT);self.assertIn("supabase.rpc('update_precheckin_reservation_state'",EDIT)
  for forbidden in ('.from(','set_expected_return_state','daily_rate *','weekly_rate *','monthly_rate *'):self.assertNotIn(forbidden,EDIT)
  for editable in ('Scheduled start','Scheduled return','Service advisor','RO number','Notes'):self.assertIn(editable,EDIT)
  for heading in ('Authoritative Reservation','Authoritative Transportation Event'):self.assertIn(heading,EDIT)
  for nested in ('result.reservation','result.transportation_event'):self.assertIn(nested,EDIT)
  self.assertIn('populate(loaded.find(item=>item.reservationId===selected.reservationId)',EDIT)
  self.assertIn('slice(0,23)',EDIT);self.assertIn('step="0.001"',EDIT)
if __name__=='__main__':unittest.main()
