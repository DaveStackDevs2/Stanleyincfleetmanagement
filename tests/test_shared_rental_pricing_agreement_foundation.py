import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260812120000_verified_shared_rental_pricing_agreement_foundation.sql"
SQL = MIGRATION.read_text()
LOWER = SQL.lower()


class SharedPricingAgreementContractTests(unittest.TestCase):
    def test_migration_is_data_free_and_fails_closed(self):
        self.assertNotIn("update public.quotes set reservation_type", LOWER)
        self.assertNotRegex(LOWER, r"reservation_type\s*=\s*'rental'")
        self.assertIn("alter column reservation_type set not null", LOWER)
        self.assertNotRegex(LOWER, r"insert into public\.(customers|vehicles|billing_lines)")

    def test_exact_schema_object_names_and_privileges(self):
        names = (
            "ux_rental_pricing_agreements_quote", "ux_rental_pricing_agreements_reservation",
            "ux_rental_pricing_agreements_transportation_event", "trg_rental_pricing_agreements_set_updated_at",
            "ck_rental_pricing_agreements_origin", "ck_rental_pricing_agreements_vehicle_class",
            "ck_rental_pricing_agreements_initial_plan", "ck_rental_pricing_agreements_current_plan",
            "ck_rental_pricing_agreements_daily_rate", "ck_rental_pricing_agreements_weekly_rate",
            "ck_rental_pricing_agreements_monthly_rate", "ck_rental_pricing_agreements_initial_plan_rate",
            "ck_rental_pricing_agreements_current_plan_rate", "ck_rental_pricing_agreements_origin_link",
            "billing_lines_pricing_agreement_id_fkey", "ck_billing_lines_pricing_snapshot_complete",
            "ck_billing_lines_rate_plan_snapshot", "ck_billing_lines_rate_amount_snapshot",
            "ix_billing_lines_pricing_agreement_id", "ck_rental_rate_rules_monthly_requires_weekly",
        )
        for name in names:
            self.assertIn(name, LOWER)
        self.assertIn("enable row level security", LOWER)
        self.assertIn("revoke all on table public.rental_pricing_agreements from public,anon,authenticated", LOWER)
        self.assertIn("grant all privileges on table public.rental_pricing_agreements to service_role", LOWER)
        self.assertRegex(LOWER, r"ux_rental_pricing_agreements_transportation_event[^;]+where transportation_event_id is not null")
        self.assertIn("origin_type='walk_in' and quote_id is null and transportation_event_id is not null", LOWER)
        self.assertNotIn("origin_type='walk_in' and quote_id is null and reservation_id is not null", LOWER)
        self.assertIn("pricing_agreement_id is null and rate_plan_snapshot is null and rate_amount_snapshot is null", LOWER)
        self.assertIn("pricing_agreement_id is not null and rate_plan_snapshot is not null and rate_amount_snapshot is not null", LOWER)

    def test_exact_argument_names_order_and_defaults(self):
        patterns = (
            r"create_quote_with_pricing_agreement_state\(\s*p_customer_id uuid,p_vehicle_class text,p_start_date timestamptz,p_expected_return_datetime timestamptz,\s*p_reservation_type text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_notes text default null\)",
            r"create_reservation_with_pricing_agreement_state\(\s*p_customer_id uuid,p_vehicle_class text,p_start_date timestamptz,p_expected_return_datetime timestamptz,\s*p_reservation_type text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_service_advisor text default null,\s*p_ro_number text default null,p_notes text default null\)",
            r"create_walk_in_with_pricing_agreement_state\(\s*p_customer_id uuid,p_vehicle_class text,p_start_date timestamptz,p_expected_return_datetime timestamptz,\s*p_reservation_type text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_service_advisor text default null,\s*p_ro_number text default null,p_notes text default null\)",
            r"convert_quote_to_reservation_with_pricing_agreement_state\(\s*p_quote_id uuid,p_service_advisor text default null,p_ro_number text default null,p_notes text default null\)",
        )
        compact = re.sub(r"\s+", " ", LOWER)
        for pattern in patterns:
            self.assertRegex(compact, pattern)

    def test_live_validation_status_and_payload_contract(self):
        for phrase in ("active application user required", "aal2 authentication required", "pricing agreement management permission required", "for share", "expected return must be after start"):
            self.assertIn(phrase, LOWER)
        for status in ("quote_pricing_agreement_created", "reservation_pricing_agreement_created", "walk_in_pricing_agreement_created", "quote_converted_to_reservation", "quote_already_converted"):
            self.assertIn(status, LOWER)
        for field in ("origin_type", "reservation_status", "reservation_type", "vehicle_class", "pay_type_rule_id", "pay_type", "initial_rate_plan", "current_rate_plan", "daily_rate", "weekly_rate", "monthly_rate", "pricing_started_at"):
            self.assertIn("'" + field + "'", LOWER)
        quote = LOWER.split("create or replace function public.create_quote_with_pricing_agreement_state", 1)[1].split("end;$function$;", 1)[0]
        self.assertIn("'active'", quote)
        self.assertNotIn("'quote',nullif", quote)
        self.assertIn("'reservation_type',p_reservation_type", quote)
        self.assertEqual(LOWER.count("exception when invalid_text_representation"), 6)
        self.assertEqual(LOWER.count("'rental rate card not configured' using errcode='p0001'"), 3)
        self.assertIn("updated_at=v_at", LOWER)
        self.assertNotIn("updated_at=now()", LOWER)

    def test_conversion_continuity_and_idempotency(self):
        fn = LOWER.split("create or replace function public.convert_quote_to_reservation_with_pricing_agreement_state", 1)[1].split("end;$function$;", 1)[0]
        for phrase in ("origin_type<>'quote'", "not v_agreement.is_active", "source_type<>'quote'", "source_id is distinct from v_quote.id", "v_event.status<>'active'", "for update", "for share", "reservation_id is distinct from", "transportation_event_id is distinct from"):
            self.assertIn(phrase, fn)
        self.assertNotIn("create_transportation_event_state", fn)
        self.assertNotIn("pay_type_rule_id and is_active=true", fn)
        self.assertIn("not v_quote.is_active or v_quote.status<>'active'", fn)
        self.assertIn("v_quote.customer_id is null", fn)
        self.assertIn("v_quote.customer_id,v_agreement.vehicle_class", fn)
        self.assertIn("'reservation_status','quote'", fn)
        self.assertIn("'reservation_type',v_quote.reservation_type", fn)
        self.assertNotIn("'reservation_status',v_reservation.status", fn)
        self.assertNotIn("'reservation_type',v_reservation.reservation_type", fn)

    def test_audit_and_function_boundaries(self):
        for action in ("pricing_agreement_created", "quote_converted_to_reservation", "pricing_agreement_activated", "pricing_plan_changed", "pricing_agreement_deactivated", "pricing_agreement_reactivated", "pricing_agreement_updated"):
            self.assertIn(action, LOWER)
        self.assertIn("coalesce(new.updated_by::text,new.created_by::text,auth.uid()::text,'system:rental_pricing_agreement')", LOWER)
        self.assertIn("revoke all on function public.audit_rental_pricing_agreement_state() from public,anon,authenticated,service_role", LOWER)
        self.assertEqual(LOWER.count("create or replace function public.update_admin_rental_rate_card_state"), 1)
        self.assertNotIn("set_admin_rental_rate_card_enabled_state", LOWER)
        self.assertIn("effective_from,created_by,updated_by", LOWER)
        self.assertIn("values(btrim(p_vehicle_class),null,p_daily_rate,p_weekly_rate,p_monthly_rate,p_sort_order,true,clock_timestamp()", LOWER)
        self.assertEqual(LOWER.count("v_observed_at:=clock_timestamp()"), 2)
        for rate in ("daily", "weekly", "monthly"):
            self.assertIn(f"{rate} rate must be a finite amount zero or greater", LOWER)

        audit = LOWER.split("create or replace function public.audit_rental_pricing_agreement_state", 1)[1].split("end;$function$;", 1)[0]
        self.assertNotIn("to_jsonb(", audit)
        material_fields = (
            "origin_type", "quote_id", "reservation_id", "transportation_event_id", "vehicle_class",
            "rental_rate_rule_id", "pay_type_rule_id", "initial_rate_plan", "current_rate_plan",
            "daily_rate_snapshot", "weekly_rate_snapshot", "monthly_rate_snapshot", "pricing_started_at", "is_active",
        )
        for field in material_fields:
            self.assertIn(f"'{field}'", audit)
        metadata = audit.split("jsonb_build_object('quote_id'", 1)[1]
        self.assertNotIn("'origin_type'", metadata)
        self.assertNotIn("'old'", metadata)
        self.assertNotIn("'new'", metadata)

    def test_frontend_monthly_without_weekly_validation(self):
        message = "Weekly rate is required when a monthly rate is configured"
        self.assertGreaterEqual(SQL.count(message), 2)
        frontend = (ROOT / "frontend/src/admin/PayTypeManagement.tsx").read_text()
        self.assertIn(message, frontend)
        self.assertIn("monthlyRate !== null && weeklyRate === null", frontend)


if __name__ == "__main__":
    unittest.main()
