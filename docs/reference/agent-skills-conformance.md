# Agent Skills conformance

Every promoted skill in `augments-labs/skills` follows the open Agent Skills specification (`agentskills.io`) and adds stricter house rules enforced by `scripts/validate.sh`.

## Open specification compliance

Each skill lives in its own directory containing a `SKILL.md` file with YAML frontmatter and optional `references/`, `scripts/`, and `assets/` subdirectories:

- `name` is 1 to 64 characters of lowercase kebab-case (`a-z`, `0-9`, single hyphens) matching the directory name.
- `description` is 1 to 1,024 characters describing when to load the skill and when to skip it.
- Optional standard keys (`license`, `compatibility`, `metadata`, `allowed-tools`) are supported.
- Explicit user-invoked skills may also set `disable-model-invocation: true` alongside explicit manual-only wording in `description`.
- No inline `hooks:` block is ever placed inside `SKILL.md` frontmatter. Hooks live in pack-level adapters under `hooks/<pack>/` so every skill folder stays portable across harnesses.

## Stricter house limits

To keep context overhead predictable and prevent skill creep, `scripts/validate.sh` enforces tighter bounds than the base spec:

| Rule | Limit or requirement |
| --- | --- |
| `description` quoting | Must be a double-quoted YAML string so `: ` and `#` never break strict YAML parsers |
| Skill body lines | At most 200 lines (strict mode warns above 160; target 80 to 150) |
| Skill body size | At most 8,000 bytes (roughly 2,000 tokens) |
| Pack description budget | Auto-triggered <= 3,400 chars, user-invoked <= 2,400 chars, combined <= 5,800 chars |
| Built-in command names | Skill names must not shadow built-in harness slash commands (`review`, `simplify`, `plan`, `help`, `clear`, `compact`, and similar) |
| Support-file load conditions | Every mention of `references/` or `assets/` in `SKILL.md` must state when to load it (`when`, `if`, `before`, `after`) |
| Reference depth | At most 1 level deep (a reference file does not chain to another reference file) |
| Dangling references | Skills may reference only promoted skills and support files that exist inside their folder; no links to `docs/` |
| Zero runtime dependencies | Scripts and hooks use only standard system tools (`bash`, POSIX `awk`, `git`) |
| No custom metadata ledgers | No hidden library folders, append-only status logs, or shouting banners |
