import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
MIGRATIONS = {
    ROOT
    / "supabase/migrations/20260731120000_phase_1_start_assign_bill_security_checkpoint.sql": 3,
    ROOT
    / "supabase/migrations/20260731170000_phase_1_continuation_reassignment_security_checkpoint.sql": 3,
}
OUTER_END = re.compile(
    r"^\s*end(?P<semicolon>;?)\s*\n\s*\$[A-Za-z_][A-Za-z0-9_]*\$;",
    re.IGNORECASE | re.MULTILINE,
)


class MigrationBlockTerminatorTest(unittest.TestCase):
    def test_outer_block_ends_have_semicolons(self) -> None:
        for migration, expected_count in MIGRATIONS.items():
            with self.subTest(migration=migration.name):
                matches = list(OUTER_END.finditer(migration.read_text()))
                self.assertEqual(expected_count, len(matches))
                missing = [match.group(0) for match in matches if not match.group("semicolon")]
                self.assertEqual([], missing)


if __name__ == "__main__":
    unittest.main()
