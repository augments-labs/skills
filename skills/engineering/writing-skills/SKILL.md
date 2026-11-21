---
name: writing-skills
description: "Use when creating, editing, or repairing an agent skill (a SKILL.md and its folder): writing or checking its frontmatter or description, adding, moving, or merging its sections, adding a reference, script, or asset file and linking it, trimming it, fixing one that never loads or triggers, or turning a runbook or a repo's recurring failures into a project skill. A skill about migrations, deploys, or rollbacks is still a skill to edit, not that task to do. Skip when only following a skill or doing the task it describes, and for docs that are not agent skills, such as a README or a plain runbook."
---

# Writing skills

A skill is a folder holding `SKILL.md`: frontmatter an agent reads to decide
whether to load the skill, and a body it follows once loaded, plus optional
`references/`, `scripts/`, and `assets/`. Write only what changes what an
agent does.

For a typo or a one-line wording fix in a body, make the edit and stop. Run
the check in Step 5 only when you touched the frontmatter or a file path.

## Step 1: Frontmatter that loads

A loader that cannot parse the frontmatter drops the skill without an error,
so a skill that "never triggers" may simply never load. Fix loading before
rewording anything.

1. `name`: lowercase letters, digits, and single hyphens, at most 64
   characters, and exactly the directory's name.
2. `description`: 1 to 1,024 characters saying when to use the skill and when
   to skip it. An agent decides from the name and description alone, matching
   them against the request in front of it, so write a trigger, not a summary
   of the steps:
   - Name the situations as people report them: symptoms, alert names, error
     text, and plain requests. Most requests describe a symptom and never name
     the procedure, so the procedure's name or a team codename alone misses
     them; give the plain words too.
   - End with `Skip` and the nearest look-alike requests the skill must not
     take.
   - Before you finish, write five requests that need the skill, at least
     three that never name it, and three near misses. Each request that needs
     the skill must match a situation in the description; no near miss may.
3. Wrap `description` in double quotes. Unquoted, a `: ` or ` #` anywhere in
   it, continuation lines included, or a leading `*`, `&`, `[`, `{`, `!`,
   `|`, `>`, `%`, `@`, or backtick, makes the YAML invalid or cuts the text.
4. Keep top-level keys to `name`, `description`, `license`, `compatibility`,
   `metadata`, and `allowed-tools`.

## Step 2: A body agents follow

1. Write instructions in the order the agent acts: numbered steps, each
   outcome as "If X, do Y". An agent can obey an instruction; it cannot obey
   a fact or a history.
2. Keep every hard stop and destructive-action guard in `SKILL.md` itself,
   whether the original bolds it or buries it in a paragraph. Agents skim, and
   they rarely open a support file at the moment the guard matters.
3. Keep each guard whole: its trigger, its action, and its numbers
   (thresholds, time windows, versions).
4. Aim for 80 to 200 lines. Cut background, history, rationale, FAQ answers
   that repeat a step, and optional courtesies before you cut a step.

## Step 3: Trimming an existing skill

1. Before cutting, list every guard in the original. Search for `never`,
   `don't`, `do not`, `stop`, `must`, `only`, `until`, `at once`, and
   `instead`, and read the prose around each hit; the buried ones matter most.
2. Cut or move everything else first. Move lookup material (history,
   glossary, long examples, tables) to `references/` only if an agent still
   needs it.
3. After cutting, check the list against the new `SKILL.md`, guard by guard,
   and restore any that went missing or lost its numbers.

## Step 4: Project skills that check a repo

When you turn incidents, postmortems, or review comments into a project
skill with a check script:

1. List every shape the failure has taken: each directory it happened in,
   each statement or file pattern, and each near miss, such as a required
   line that was present but in the wrong place.
2. Make the check cover the whole repo, every matching directory, not only
   the files from the last incident or the current diff.
3. Calibrate each shape. In a scratch copy of the repo, plant the failure
   under a new name, run the check, and watch it exit non-zero naming the
   file. Then run it on the clean repo and watch it exit 0. Delete the
   scratch copy.
4. A check you never saw fail proves nothing. An `exit` inside a piped
   `while` loop, a glob that matches nothing, and a pattern that only matches
   the old file name all pass silently.
5. In the skill body, state the exact command to run the check and when to
   run it.

## Step 5: Support files and the check

1. Put files the agent reads to decide in `references/`, files it fills in or
   copies in `assets/`, and code it runs in `scripts/`.
2. Name every support file from `SKILL.md` on a line that also says when to
   read or run it (`when`, `if`, `before`, `after`). A file `SKILL.md` never
   names is never read, and a named file that does not exist is a dead end.
3. Keep support files one level deep: they do not point to other support
   files.
4. Run this skill's checker on the skill directory, fix each `FAIL`, and run
   it again:

```bash
bash scripts/check-skill.sh path/to/skill
```

5. Re-read the description last. If it lists steps instead of when to use
   the skill, rewrite it.

## Gotchas

- A strict YAML loader rejects `description: Use when: X` and truncates
  `description: Fix issue #12` at the `#`. Quoting fixes both.
- A `name` that differs from its directory by one letter, such as a missing
  plural `s`, can keep the skill from loading.
- `SKILL.md` is case-sensitive; `skill.md` is not found on most systems.
- A guard moved to `references/` is a guard lost for an agent that never
  opens that file.
