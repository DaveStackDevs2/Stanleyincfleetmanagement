import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/'frontend/src/reservations/ReservationsWorkspace.tsx').read_text()
CHECKIN=(ROOT/'frontend/src/reservations/PickupWorkspace.tsx').read_text()
SQL=(ROOT/'supabase/migrations/20260818170000_verified_checkin_scheduled_billing_and_workspace.sql').read_text()
LOWER=SQL.lower()
PICKUP=LOWER.split('create or replace function public.get_billing_workspace_state',1)[0]
WORKSPACE=LOWER.split('create or replace function public.get_billing_workspace_state',1)[1]
class CheckinFrontendTests(unittest.TestCase):
 def test_product_wording_and_authoritative_rpcs(self):
  self.assertIn("'Check-in / Pickup'",UI);self.assertIn('Scheduled start',CHECKIN);self.assertIn('Scheduled return',CHECKIN);self.assertIn('Actual pickup / handoff time',CHECKIN)
  self.assertIn('get_pricing_agreement_pickup_state',CHECKIN);self.assertIn('activate_pricing_agreement_pickup_state',CHECKIN)
  self.assertNotIn('start_reservation_vehicle_use_state',CHECKIN);self.assertNotIn('create_billing_parent_line_state',CHECKIN);self.assertNotIn('.from(',CHECKIN)
 def test_timing_validation_and_exact_results(self):
  self.assertIn("c.state==='ready'",CHECKIN);self.assertIn("c.state!=='ready'",CHECKIN);self.assertIn('actual out cannot be earlier',CHECKIN.lower());self.assertIn('nonnegative integer',CHECKIN.lower());self.assertIn('weekly/monthly',CHECKIN.lower())
  self.assertIn("actual_out_at:'Actual physical handoff'",CHECKIN);self.assertIn("pricing_started_at:'Scheduled billing / pricing start'",CHECKIN);self.assertIn("billing_start:'Billing preview start'",CHECKIN);self.assertIn("vehicle_class:'Vehicle model'",CHECKIN)
  self.assertNotRegex(CHECKIN,r'(daily_rate|subtotal|tax_rate|tax_amount|total)\s*[*/]')
class ScheduledBillingMigrationTests(unittest.TestCase):
 def test_pickup_uses_existing_engine_and_distinct_times(self):
  self.assertIn('public.start_reservation_vehicle_use_state(v_reservation.id,p_vehicle_id,p_actual_out_at)',PICKUP)
  self.assertIn("public.activate_case_billing_state(v_reservation.id,v_rate_amount,null,null,null,'initial_assignment','pricing_agreement_daily',v_pay_type.pay_type)",PICKUP)
  self.assertNotIn('create_billing_parent_line_state',PICKUP);self.assertIn('line.start_time is not distinct from v_reservation.start_date',PICKUP)
  self.assertIn('pricing_started_at=v_reservation.start_date',PICKUP);self.assertIn("'actual_out_at',p_actual_out_at",PICKUP);self.assertIn("'pricing_started_at',v_reservation.start_date",PICKUP)
  for snapshot in ('pricing_agreement_id=v_agreement.id',"rate_plan_snapshot='daily'",'rate_amount_snapshot=v_rate_amount','default_daily_rate_snapshot=v_agreement.daily_rate_snapshot'):self.assertIn(snapshot,PICKUP)
 def test_pickup_security_boundary(self):
  self.assertIn("security definer set search_path to ''",PICKUP);self.assertIn('owner to postgres',LOWER);self.assertIn('from public,anon',LOWER);self.assertIn('to authenticated,service_role',LOWER)
 def test_locked_vehicle_is_currently_available(self):
  lookup='select * into v_vehicle from public.vehicles where id=p_vehicle_id and is_retired=false for update;'
  availability="if v_vehicle.status is distinct from 'available' then"
  start='public.start_reservation_vehicle_use_state(v_reservation.id,p_vehicle_id,p_actual_out_at)'
  self.assertIn(lookup,PICKUP);self.assertIn(availability,PICKUP)
  self.assertLess(PICKUP.index(lookup),PICKUP.index(availability));self.assertLess(PICKUP.index(availability),PICKUP.index(start))
  self.assertIn("'selected vehicle is not available for pickup'",PICKUP)
 def test_workspace_reuses_operational_eligibility(self):
  self.assertIn('v_operational jsonb',WORKSPACE);self.assertIn('get_transportation_event_operational_payload_state(v_case.transportation_event_id)',WORKSPACE)
  check=WORKSPACE.index("v_operational -> 'current_continuity'");billing=WORKSPACE.index("v_operational -> 'current_billing_lines'");cont=WORKSPACE.index('continue;',billing);count=WORKSPACE.index('v_case_count := v_case_count + 1;',cont)
  self.assertLess(check,billing);self.assertLess(billing,cont);self.assertLess(cont,count);self.assertIn('and jsonb_array_length',WORKSPACE[billing-120:cont])
  event_query=WORKSPACE[WORKSPACE.index('for v_case in'):WORKSPACE.index('loop',WORKSPACE.index('for v_case in'))]
  self.assertNotRegex(event_query,r'exists\s*\([^)]*billing_lines')
  self.assertIn('normal pre-check-in reservations',LOWER);self.assertNotIn('aal2 authentication is required',WORKSPACE);self.assertIn('reservation.ro_number',WORKSPACE)
 def test_no_controlled_data_or_vehicle_status_mutation(self):
  self.assertNotRegex(LOWER,r'1e6be455|test-stock|test-vin');self.assertNotIn('update public.vehicles',LOWER)
if __name__=='__main__':unittest.main()
