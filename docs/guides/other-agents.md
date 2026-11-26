# Using the skills on another agent

Every skill in `engineering-skills` follows the open Agent Skills format (`SKILL.md` with YAML frontmatter and optional `references/` and `scripts/` subdirectories). Even if your coding agent is not one of the 11 harnesses with a dedicated plugin manifest, you can still install and use the skills.

## Option 1: Install with `npx skills add`

If your agent reads standard `.agents/skills/` or user skill folders supported by the `skills` CLI, run:

```bash
npx skills add augments-labs/skills/plugins/engineering-skills
```

## Option 2: Copy the flat skill folders directly

Clone the repository and copy the promoted skills from `plugins/engineering-skills/skills/` into whichever folder your agent scans for skills (commonly `.agents/skills/` inside a project or your agent's global skills directory):

```bash
git clone https://github.com/augments-labs/skills.git
cp -R skills/plugins/engineering-skills/skills/* /path/to/your/agent/skills/
```

Copy from `plugins/engineering-skills/skills/`, not from the repository root `skills/` folder. The generated bundle under `plugins/engineering-skills/skills/` contains only promoted, evaluated skills in a flat layout with zero staging drafts or evaluation files.

## Option 3: Reference a skill file directly

If your agent has no automatic skill loader at all, you can point it directly at a skill file in your prompt when you need it:

```text
Read plugins/engineering-skills/skills/debugging/SKILL.md and follow it on this failing test.
```

## What about hooks?

The two guardrail hooks (`guard-destructive-git` and `guard-protected-branch`) require a harness pre-tool hook API and run in Claude Code, Codex CLI, and Antigravity. On other agents, you still get the full set of skills, and you can run the underlying hook checker manually in scripts or git hooks if you want:

```bash
bash hooks/engineering/lib/check.sh --hook guard-destructive-git --tool shell --command 'git reset --hard'
```

It exits `0` to allow and `2` to deny, printing the reason to stderr.
