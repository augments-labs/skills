"""The player character."""

SKILL_COSTS = {"fireball": 3, "heal": 2, "parry": 1, "sprint": 1}


class Player:
    def __init__(self, name, skill_points=5):
        self.name = name
        self.skill_points = skill_points
        self.skills = []

    def learn_skill(self, skill):
        """Spend skill points to learn `skill`."""
        cost = SKILL_COSTS[skill]
        if cost > self.skill_points:
            raise ValueError(f"{skill} costs {cost}, {self.name} has {self.skill_points}")
        self.skill_points -= cost
        self.skills.append(skill)

    def knows(self, skill):
        return skill in self.skills
