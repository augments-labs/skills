# How skills load

Every skill in `engineering-skills` is a folder containing a `SKILL.md` file and, when helpful, small support files under `references/` or `scripts/`. Understanding how your agent reads those files explains why this library keeps descriptions short, bodies lean, and support files loaded on demand.

## Three layers of context

When you start a session, your agent does not dump every skill file into the prompt. Instead, it uses progressive disclosure:

1. **Catalogue metadata (always visible):** At startup, the harness reads only the `name` and `description` from each installed skill's frontmatter. With the five promoted skills currently in `engineering-skills`, those descriptions total about 2,619 characters (roughly 655 tokens).
2. **Skill body (loaded on demand):** When your request matches a skill's description, the agent reads the full `SKILL.md` body. Every promoted skill body in this pack is capped at 200 lines and 8,000 bytes (roughly 2,000 tokens), so loading one skill stays well inside harness compaction limits.
3. **Support files (loaded only on a trigger condition):** Reference notes and helper scripts sit under `references/` and `scripts/` inside the skill folder. `SKILL.md` names them only next to a concrete condition (for example, loading `references/probabilistic-evidence.md` when a failure is intermittent or timing-dependent). On ordinary tasks, those files cost zero tokens.

## Why descriptions include a Skip clause

Routing happens from `name` and `description` alone. A vague description makes an agent load a heavy workflow for a one-line typo fix, slowing down simple tasks and burning tokens.

Every auto-triggered skill in this pack ends its description with an explicit `Skip` boundary naming the closest look-alike requests it should ignore. For example, `debugging` skips bugs where you already pointed straight at the fix, and `test-driven-development` skips one-condition tweaks, docs, renames, and formatting.

## Calling a skill explicitly

You do not have to wait for automatic routing. If you want a specific skill on a task, name it directly in your prompt (for example, "Use the debugging skill on this failure" or via your harness's slash command syntax when supported).

## Why the pack uses `plugins/engineering-skills/`

The repository keeps canonical skills organized by pack under `skills/<pack>/<name>/` (such as `skills/engineering/debugging/`) alongside staging and evaluation folders. Most harnesses expect a flat `skills/<name>/SKILL.md` layout inside a plugin root, with zero evaluation or staging files mixed in. The generated bundle under `plugins/engineering-skills/` gives every supported harness that clean flat structure while keeping future domain packs isolated from each other.
