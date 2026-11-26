# Authoring project skills

The `writing-skills` skill helps your agent create, trim, repair, and verify Agent Skills (`SKILL.md` folders). Its most useful day-to-day job in a team repository is turning your own runbooks, incident postmortems, and recurring code-review comments into repo-local project skills.

## When it loads (and when it skips)

`writing-skills` loads when you ask your agent to write or edit a `SKILL.md` and its folder, fix a skill that never loads or triggers, trim a long skill without losing safety rules, add a `references/` or `scripts/` file, or convert a runbook or recurring failure into a project skill.

It skips when you are only following an existing skill, doing the task that skill describes, or editing ordinary documentation like a README or plain runbook.

## What the agent does differently

1. **Fixes loading defects before touching wording.** A strict YAML parser drops a skill silently if `description` is unquoted around `: ` or `#`, or if `name` differs from the directory name by even one character. The agent checks frontmatter syntax and naming first.
2. **Writes trigger descriptions, not step summaries.** An agent decides whether to load a skill from its name and description alone. The skill guides your agent to name the concrete symptoms, alerts, and plain requests people actually type, end with a `Skip` clause for near-misses, and sanity-check the wording against five real requests and three near-misses.
3. **Keeps every guard intact when trimming.** When shrinking an oversized skill, the agent lists every `never`, `stop`, `must`, `only`, and numeric threshold in the original before cutting background prose, then verifies every guard survived inside `SKILL.md` itself (never buried in a reference file an agent might skip).
4. **Calibrates repo check scripts against real failures.** When building a project skill that ships a check script, the agent makes the script scan the whole repository (not just one directory or the current diff), plants each failure shape in a scratch copy under a new filename to watch the check fail, verifies it passes on a clean tree, and deletes the scratch copy.
5. **Runs `scripts/check-skill.sh` before finishing.** The skill ships with its own portable checker script and runs it against the skill directory until every `FAIL` is fixed.

## Example prompts

```text
Turn the lessons in docs/incidents.md into a project skill under .agents/skills/ with a check script CI can run before deploys.
```

```text
Our deploying skill in .agents/skills/ is over 300 lines and agents skim past steps. Trim SKILL.md under 120 lines without losing any safety guard.
```

```text
The db-migrations skill in .agents/skills/ never triggers when agents touch migrations. Find out why and fix it.
```
