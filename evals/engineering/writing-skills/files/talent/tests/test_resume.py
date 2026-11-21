import unittest

from talent.match import score
from talent.resume import skills

RESUME = """Experience
- Backend engineer, 2019-2024

Skills
- Python
- SQL
- Docker
"""


class ResumeTest(unittest.TestCase):
    def test_skills(self):
        self.assertEqual(skills(RESUME), ["Python", "SQL", "Docker"])

    def test_score(self):
        self.assertEqual(score(RESUME, ["python", "go"]), 0.5)


if __name__ == "__main__":
    unittest.main()
