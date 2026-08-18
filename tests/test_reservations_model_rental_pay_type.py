import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = (ROOT / "frontend/src/reservations/ReservationsWorkspace.tsx").read_text()
MIGRATION = ROOT / "supabase/migrations/20260818120000_verified_reservations_model_rental_pay_type.sql"
SQL = MIGRATION.read_text()
LOWER_UI = UI.lower()
LOWER_SQL = SQL.lower()


class ReservationsModelRentalPayTypeTests(unittest.TestCase):
    def test_vehicle_model_copy_preserves_backend_compatibility_contract(self):
        self.assertIn("Vehicle model", UI)
        self.assertIn("Select vehicle model", UI)
        self.assertIn("vehicle model is required", UI)
        self.assertIn("Type / model", UI)
        self.assertNotIn("Select configured class", UI)
        self.assertNotIn("Vehicle class", UI)
        self.assertIn("row!.vehicle_class", UI)
        self.assertIn("pricing.vehicle_class", UI)
        self.assertIn("p_vehicle_class:vehicleModel.trim()", UI)

    def test_authoritative_rental_pay_type_ui_rules(self):
        self.assertIn("item.name.trim().toLowerCase() === 'rental'", UI)
        self.assertIn("rentalPayType ? [rentalPayType] : []", UI)
        self.assertIn("item.name.trim().toLowerCase() !== 'rental'", UI)
        self.assertIn("setPayTypeId(rentalPayType.id)", UI)
        self.assertIn("else{setPayTypeId('');setError(null)}", UI)
        self.assertIn("the active Rental pay type is required", UI)
        self.assertIn("disabled={!reservationType", UI)
        self.assertNotRegex(UI, r"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")

    def test_frontend_does_not_add_business_arithmetic_or_direct_mutations(self):
        self.assertNotRegex(UI, r"\.from\(")
        self.assertNotRegex(LOWER_UI, r"(?:daily|weekly|monthly|tax)\s*[+*/-]")
        self.assertEqual(
            sum(path.read_text().count("createClient(") for path in (ROOT / "frontend/src").rglob("*.ts*")),
            1,
        )

    def test_create_vehicle_repair_and_signature(self):
        compact = re.sub(r"\s+", " ", LOWER_SQL)
        self.assertRegex(compact, r"create or replace function public\.create_vehicle_state\( p_vin text, p_stock_number text, p_model text, p_fleet_type text, p_mileage integer, p_current_tag text, p_fleet_conversion_type text, p_location text default null, p_notes text default null, p_status text default 'available', p_recon_status text default 'clean' \) returns jsonb")
        self.assertIn("vin_last8", LOWER_SQL)
        self.assertIn("right(btrim(p_vin), 8)", LOWER_SQL)
        self.assertIn("char_length(btrim(p_vin)) < 8", LOWER_SQL)
        self.assertIn("vin must contain at least 8 characters", LOWER_SQL)
        self.assertNotIn("vin must be at least 8 characters", LOWER_SQL)
        self.assertIn("security invoker", LOWER_SQL)
        self.assertIn("set search_path to ''", LOWER_SQL)
        self.assertIn("from public, anon, authenticated", LOWER_SQL)

    def test_bidirectional_trigger_invariant_is_recorded(self):
        self.assertIn("enforce_pricing_agreement_transportation_pay_type_state", LOWER_SQL)
        self.assertIn("rental workflow requires the rental pay type", LOWER_SQL)
        self.assertIn("rental pay type requires a rental workflow", LOWER_SQL)
        self.assertIn("if new.reservation_id is not null", LOWER_SQL)
        self.assertIn("elsif new.quote_id is not null", LOWER_SQL)
        fallback = re.sub(r"\s+", " ", LOWER_SQL)
        self.assertIn(
            "select reservation_record.reservation_type into v_transportation_type "
            "from public.reservations as reservation_record "
            "where reservation_record.transportation_event_id = new.transportation_event_id "
            "order by reservation_record.created_at, reservation_record.id limit 1;",
            fallback,
        )
        self.assertIn("from public.pay_type_rules", LOWER_SQL)
        self.assertIn("pricing agreement transportation type was not found", LOWER_SQL)
        self.assertIn("pricing agreement pay type was not found", LOWER_SQL)
        self.assertEqual(LOWER_SQL.count("using errcode = '22023'"), 4)
        self.assertIn("drop trigger if exists trg_rental_pricing_agreements_transportation_pay_type", LOWER_SQL)
        self.assertIn("on public.rental_pricing_agreements", LOWER_SQL)
        self.assertIn("before insert or update of pay_type_rule_id, reservation_id, quote_id, transportation_event_id", LOWER_SQL)

    def test_verified_live_function_security_metadata_is_recorded(self):
        compact = re.sub(r"\s+", " ", LOWER_SQL)
        create_vehicle_signature = "public.create_vehicle_state(text,text,text,text,integer,text,text,text,text,text,text)"
        trigger_signature = "public.enforce_pricing_agreement_transportation_pay_type_state()"
        self.assertIn(f"alter function {create_vehicle_signature} owner to postgres", compact)
        self.assertIn(
            f"revoke all on function {create_vehicle_signature} from public, anon, authenticated; "
            f"grant execute on function {create_vehicle_signature} to service_role;",
            compact,
        )
        self.assertIn(f"alter function {trigger_signature} owner to postgres", compact)
        self.assertIn(
            f"revoke all on function {trigger_signature} from public, anon, authenticated, service_role; "
            f"grant execute on function {trigger_signature} to public, service_role;",
            compact,
        )

    def test_migration_is_data_free(self):
        self.assertNotRegex(LOWER_SQL, r"insert into public\.(pay_type_rules|customers|reservations|quotes|rental_pricing_agreements|rental_rate_rules)")
        for value in ("test-stock-002", "test-vin-002", "test-stock-003", "test-vin-003"):
            self.assertNotIn(value, LOWER_SQL)


if __name__ == "__main__":
    unittest.main()
