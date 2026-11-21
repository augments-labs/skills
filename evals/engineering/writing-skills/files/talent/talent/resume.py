"""Plain-text resume parsing."""
import re

HEADING = re.compile(r"^(Experience|Education|Skills)\s*:?\s*$", re.I)


def sections(text):
    """Split a resume into {heading: [lines]} by its section headings."""
    out, current = {}, None
    for line in text.splitlines():
        m = HEADING.match(line.strip())
        if m:
            current = m.group(1).title()
            out[current] = []
        elif current and line.strip():
            out[current].append(line.strip().lstrip("-* ").strip())
    return out


def skills(text):
    return sections(text).get("Skills", [])
