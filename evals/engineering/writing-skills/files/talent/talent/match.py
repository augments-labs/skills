"""Scores a resume against a job's required skills."""
from talent.resume import skills


def score(resume_text, required):
    have = {s.lower() for s in skills(resume_text)}
    return sum(1 for r in required if r.lower() in have) / len(required) if required else 0.0
