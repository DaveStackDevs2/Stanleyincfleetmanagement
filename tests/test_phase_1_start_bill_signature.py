import re
import unittest
from pathlib import Path


MIGRATION = (
    Path(__file__).parents[1]
    / "supabase/migrations/20260731120000_phase_1_start_assign_bill_security_checkpoint.sql"
)
FUNCTION_NAME = "public.create_start_bill_case_and_get_payload_state"
EXPECTED_TYPES = [
    "text", "text", "timestamptz", "timestamptz", "text", "text", "text",
    "text", "text", "integer", "text", "text", "timestamptz", "numeric",
    "numeric", "timestamptz", "timestamptz", "text", "text", "jsonb", "text",
    "text", "text", "text", "text", "text", "text", "text", "text", "text",
    "text", "text", "text", "integer", "uuid",
]


def parameter_types(parameter_list: str) -> list[str]:
    parameters = [parameter.strip() for parameter in parameter_list.split(",")]
    return [re.split(r"\s+", parameter, maxsplit=2)[1].lower() for parameter in parameters]


def identity_types(parameter_list: str) -> list[str]:
    return [parameter.strip().lower() for parameter in parameter_list.split(",")]


class StartBillSignatureTest(unittest.TestCase):
    def test_static_identities_match_create_signature(self) -> None:
        sql = MIGRATION.read_text()
        create_match = re.search(
            rf"create or replace function\s+{re.escape(FUNCTION_NAME)}\s*\((.*?)\)\s*returns",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        self.assertIsNotNone(create_match)
        create_types = parameter_types(create_match.group(1))
        self.assertEqual(35, len(create_types))
        self.assertEqual(EXPECTED_TYPES, create_types)

        identity_matches = re.findall(
            rf"(?:alter function|revoke all on function|grant execute on function)\s+"
            rf"{re.escape(FUNCTION_NAME)}\s*\((.*?)\)\s*(?:owner|from|to)",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        self.assertEqual(3, len(identity_matches))
        for identity in identity_matches:
            types = identity_types(identity)
            self.assertEqual(35, len(types))
            self.assertEqual(create_types, types)


if __name__ == "__main__":
    unittest.main()
