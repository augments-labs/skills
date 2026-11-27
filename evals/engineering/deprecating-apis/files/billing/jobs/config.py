import json
import os

PATH = os.path.join(os.path.dirname(__file__), "..", "config", "jobs.json")


def load(job):
    with open(PATH) as f:
        return json.load(f)[job]
