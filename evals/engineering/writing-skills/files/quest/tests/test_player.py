import unittest

from game.player import Player


class LearnSkillTest(unittest.TestCase):
    def test_learning_spends_points(self):
        p = Player("ayla")
        p.learn_skill("heal")
        self.assertEqual(p.skill_points, 3)
        self.assertTrue(p.knows("heal"))

    def test_too_expensive(self):
        p = Player("ayla", skill_points=1)
        with self.assertRaises(ValueError):
            p.learn_skill("fireball")


if __name__ == "__main__":
    unittest.main()
