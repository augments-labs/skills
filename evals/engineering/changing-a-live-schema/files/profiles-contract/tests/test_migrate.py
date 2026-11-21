import migrate
from tests.helpers import DbTest


class MigrateTest(DbTest):
    def test_second_run_applies_nothing(self):
        self.assertEqual(migrate.migrate(self.conn), [])

    def test_every_file_is_recorded(self):
        names = {row[0] for row in self.conn.execute("SELECT name FROM schema_migrations")}
        files = {p.name for p in migrate.MIGRATIONS.glob("*.sql")}
        self.assertEqual(names, files)
