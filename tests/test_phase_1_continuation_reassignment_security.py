import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
MIGRATION = ROOT / "supabase/migrations/20260731170000_phase_1_continuation_reassignment_security_checkpoint.sql"
FUNCTIONS = {
    "public.continue_case_same_vehicle_and_get_unified_payload_state": ["uuid", "timestamptz"],
    "public.reassign_active_case_to_vehicle_and_get_unified_payload_state": [
        "uuid", "uuid", "timestamptz", "uuid", "boolean"
    ],
    "public.restart_same_vehicle_after_gap": ["uuid", "uuid", "timestamptz"],
}
HELPERS = {
    "continue_case_same_vehicle_state": "uuid, timestamptz",
    "renew_reservation_same_vehicle_state": "uuid, timestamptz",
    "renew_same_vehicle_state": "uuid, timestamptz",
    "restart_reservation_same_vehicle_after_gap_state": "uuid, timestamptz",
    "restart_same_vehicle_after_gap": "uuid, uuid, timestamptz",
    "start_vehicle_use_state": "uuid, uuid, timestamptz",
    "reassign_active_case_to_vehicle_state": "uuid, uuid, timestamptz, uuid, boolean",
    "swap_reservation_vehicle_state": "uuid, uuid, timestamptz",
    "swap_vehicle_state": "uuid, uuid, timestamptz",
    "resolve_reservation_dependency_as_reassigned_state": "uuid, uuid",
    "resolve_transportation_event_dependency_as_reassigned_state": "uuid, uuid",
    "resolve_reservation_dependency_state": "uuid, text, uuid",
    "resolve_linked_conflicts_for_dependency_state": "uuid",
}


def create_body(sql: str, name: str) -> tuple[list[str], str]:
    match = re.search(
        rf"create or replace function\s+{re.escape(name)}\s*\((.*?)\)\s*returns jsonb(.*?)\$function\$;",
        sql, re.IGNORECASE | re.DOTALL,
    )
    if not match:
        raise AssertionError(f"CREATE FUNCTION not found: {name}")
    parameters = [part.strip() for part in match.group(1).split(",")]
    types = [re.split(r"\s+", part, maxsplit=2)[1].lower() for part in parameters]
    return types, match.group(2).lower()


class ContinuationReassignmentSecurityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text()
        cls.lower = cls.sql.lower()

    def test_static_function_identities_exactly_match_create_signatures(self) -> None:
        for name, expected in FUNCTIONS.items():
            with self.subTest(name=name):
                created, _ = create_body(self.sql, name)
                self.assertEqual(expected, created)
                identities = re.findall(
                    rf"(?:alter function|revoke all on function|grant execute on function)\s+"
                    rf"{re.escape(name)}\s*\((.*?)\)\s*(?:owner|from|to)",
                    self.sql, re.IGNORECASE | re.DOTALL,
                )
                self.assertGreaterEqual(len(identities), 3)
                for identity in identities:
                    self.assertEqual(expected, [item.strip().lower() for item in identity.split(",")])

    def test_browser_wrappers_enforce_security_boundary(self) -> None:
        for name in list(FUNCTIONS)[:2]:
            with self.subTest(name=name):
                _, body = create_body(self.sql, name)
                self.assertIn("security definer", body)
                self.assertIn("set search_path to ''", body)
                self.assertIn("au.auth_user_id = auth.uid()", body)
                self.assertIn("au.is_active = true", body)
                self.assertIn("errcode = '42501'", body)
                self.assertIn("auth.jwt() ->> 'aal'", body)
                self.assertIn("<> 'aal2'", body)

    def test_reassignment_actor_agreement_and_propagation(self) -> None:
        _, body = create_body(
            self.sql, "public.reassign_active_case_to_vehicle_and_get_unified_payload_state"
        )
        self.assertIn("p_actor_user_id <> v_actor_user_id", body)
        call = re.search(
            r"reassign_active_case_to_vehicle_state\s*\((.*?)\);", body, re.DOTALL
        )
        self.assertIsNotNone(call)
        self.assertIn("v_actor_user_id", call.group(1))

    def test_restart_helper_delegates_to_existing_engine(self) -> None:
        _, body = create_body(self.sql, "public.restart_same_vehicle_after_gap")
        self.assertIn("return public.start_vehicle_use_state(", body)
        self.assertNotIn("insert into public.vehicle_events", body)
        self.assertNotIn("insert into public.contract_periods", body)

    def test_actor_stamping_precedes_payload_load(self) -> None:
        for name in list(FUNCTIONS)[:2]:
            with self.subTest(name=name):
                _, body = create_body(self.sql, name)
                payload_at = body.index("v_unified_payload := public.get_unified_case_payload_state")
                self.assertLess(body.rindex("update public.", 0, payload_at), payload_at)
                self.assertNotIn("update public.", body[payload_at:])

    def test_complete_helper_privileges_are_service_role_only(self) -> None:
        for name, signature in HELPERS.items():
            with self.subTest(name=name):
                identity = rf"public\.{name}\({re.escape(signature)}\)"
                self.assertRegex(
                    self.lower,
                    rf"revoke execute on function {identity} from public, anon, authenticated;",
                )
                self.assertRegex(
                    self.lower, rf"grant execute on function {identity} to service_role;"
                )

    def test_checkpoint_migration_exists_exactly_once_at_expected_path(self) -> None:
        matches = sorted(
            MIGRATION.parent.glob("*phase_1_continuation_reassignment_security_checkpoint.sql")
        )
        self.assertEqual([MIGRATION], matches)
        self.assertTrue(MIGRATION.is_file())


if __name__ == "__main__":
    unittest.main()
