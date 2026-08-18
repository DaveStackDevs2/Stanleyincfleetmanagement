import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/'frontend/src/reservations/ReservationsWorkspace.tsx').read_text()
PICKUP=(ROOT/'frontend/src/reservations/PickupWorkspace.tsx').read_text()
SQL=(ROOT/'supabase/migrations/20260818160000_verified_pickup_fleet_type_compatibility.sql').read_text()
LOWER=SQL.lower()
class ReservationsPickupTests(unittest.TestCase):
 def test_authoritative_rpc_only_frontend(self):
  self.assertIn("'pickup'",UI);self.assertIn("get_pricing_agreement_pickup_state",PICKUP);self.assertIn("activate_pricing_agreement_pickup_state",PICKUP)
  self.assertNotIn('start_reservation_vehicle_use_state',PICKUP);self.assertNotIn('create_billing_parent_line_state',PICKUP);self.assertNotIn('.from(',PICKUP)
 def test_fail_closed_validation_and_candidates(self):
  self.assertIn("c.state!=='ready'",PICKUP);self.assertIn("c.state==='ready'",PICKUP);self.assertIn('actual out cannot be earlier',PICKUP.lower());self.assertIn('nonnegative integer',PICKUP.lower());self.assertIn('weekly/monthly pickup billing is not implemented yet',PICKUP.lower())
 def test_authoritative_results_and_compatibility_label(self):
  self.assertIn('billing_preview',PICKUP);self.assertIn("vehicle_class:'Vehicle model'",PICKUP);self.assertIn('vehicleModel:text(row!.vehicle_class)',PICKUP)
  self.assertNotRegex(PICKUP,r'(?i)test-(vin|stock)|1e6be455|976cc3df');self.assertNotRegex(PICKUP,r'(daily_rate|subtotal|tax_rate|tax_amount|total)\s*[*/]')
 def test_shared_client(self):
  sources=''.join(p.read_text() for p in (ROOT/'frontend/src').rglob('*') if p.suffix in {'.ts','.tsx'})
  self.assertEqual(sources.count('createClient('),1)
class FleetCompatibilityMigrationTests(unittest.TestCase):
 def test_helper_boundary_and_guard(self):
  self.assertRegex(LOWER,r'function public\.start_reservation_vehicle_use_state\(p_reservation_id uuid,p_vehicle_id uuid,p_actual_out_at timestamptz\)')
  self.assertIn('select fleet_type into v_vehicle_fleet_type from public.vehicles',LOWER);self.assertIn('lower(btrim(v_vehicle_fleet_type))<>lower(btrim(v_reservation.reservation_type))',LOWER)
  self.assertIn("vehicle fleet type % does not match reservation type %",LOWER);self.assertIn("errcode='22023'",LOWER)
  self.assertLess(LOWER.index("errcode='22023'"),LOWER.index('public.start_vehicle_use_state'))
  self.assertIn('from public,anon,authenticated',LOWER);self.assertIn('to postgres,service_role',LOWER);self.assertNotIn('security definer',LOWER)
 def test_candidate_view(self):
  self.assertIn('with (security_invoker=true)',LOWER);self.assertIn('v.model = r.requested_model',LOWER);self.assertIn('lower(btrim(v.fleet_type)) = lower(btrim(r.reservation_type))',LOWER)
  for state in ('pending_return','ready','unavailable'):self.assertIn(state,LOWER)
  self.assertNotIn('update public.vehicles',LOWER);self.assertNotRegex(LOWER,r'1e6be455|test-stock|test-vin')
if __name__=='__main__':unittest.main()
