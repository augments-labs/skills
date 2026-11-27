import os
import tempfile
import unittest

import migrate
from app.db import connect


class DbTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.conn = connect("sqlite:///" + os.path.join(self._dir.name, "test.db"))
        migrate.migrate(self.conn)

    def tearDown(self):
        self.conn.close()
        self._dir.cleanup()
