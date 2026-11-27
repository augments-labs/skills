import re
import unittest

import migrate


class MigrationFilesTest(unittest.TestCase):
    def test_names_are_numbered_in_sequence(self):
        numbers = [int(re.match(r"(\d{4})_", p.name).group(1))
                   for p in sorted(migrate.MIGRATIONS.glob("*.sql"))]
        self.assertEqual(numbers, list(range(1, len(numbers) + 1)))

    def test_every_file_has_a_statement(self):
        for path in migrate.MIGRATIONS.glob("*.sql"):
            self.assertTrue(migrate.split_statements(path.read_text()), path.name)

    def test_split_drops_comments(self):
        sql = "-- migrate:no-transaction\nCREATE INDEX a ON t (x);\n-- done\n"
        self.assertEqual(migrate.split_statements(sql), ["CREATE INDEX a ON t (x)"])
