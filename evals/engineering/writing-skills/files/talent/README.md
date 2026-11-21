# talent

Matches candidate resumes to job openings.

- `talent/resume.py`: parses a plain-text resume into sections.
- `talent/match.py`: scores a resume against a job's required skills.
- `skills.json`: the skills taxonomy, grouped by area.

```bash
python3 -m unittest discover -s tests -t .
```
