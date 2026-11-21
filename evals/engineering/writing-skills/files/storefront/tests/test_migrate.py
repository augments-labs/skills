import os
import unittest

import migrate


class PlanTest(unittest.TestCase):
    def test_core_plan_is_ordered(self):
        names = migrate.plan(os.path.join(migrate.ROOT, "migrations"))
        self.assertEqual(names, sorted(names))
        self.assertTrue(names[0].startswith("0001_"))


if __name__ == "__main__":
    unittest.main()
