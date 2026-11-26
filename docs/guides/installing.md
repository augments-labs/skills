# Installing, updating, and removing

Installation depends on the coding agent you use. If you switch between agents, install `engineering-skills` in each one.

Several harnesses install from a local clone of this repository. For those, clone it once:

```bash
git clone https://github.com/augments-labs/skills.git
```

When you are done installing, read [Your first session](first-session.md) to verify that the skills and hooks loaded.

## How the repository layout maps to plugins

This repository is a multi-pack marketplace. The repository root holds marketplace catalogs (such as `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`) that point to each pack's self-contained plugin folder under `plugins/engineering-skills/`.

That is why `.claude-plugin/marketplace.json` lives at the root while `.claude-plugin/plugin.json` lives inside `plugins/engineering-skills/.claude-plugin/`. Keeping each pack under `plugins/<pack>-skills/` gives every harness flat `skills/<name>/SKILL.md` paths and pack-scoped hooks without leaking staging skills or evaluation suites into your install.

## Claude Code

Register the marketplace and install the plugin:

```text
/plugin marketplace add augments-labs/skills
/plugin install engineering-skills@augments-labs
```

Claude Code loads both the skills and the hooks (`hooks/hooks.json`).

To update or remove:

```text
/plugin marketplace update augments-labs
/plugin update engineering-skills@augments-labs
/plugin uninstall engineering-skills@augments-labs
```

## Codex CLI

From a local clone:

```bash
codex plugin marketplace add /path/to/skills
codex plugin add engineering-skills@augments-labs
```

Codex loads both the skills and the hooks (`hooks/codex-hooks.json`). On your first session after installing or updating, Codex shows a "Hooks need review" prompt. Choose to trust the hooks so they run.

To update, run `git pull` in your clone and re-sync the plugin in Codex.

## Antigravity

Install directly from the pack folder:

```bash
agy plugin install https://github.com/augments-labs/skills/tree/main/plugins/engineering-skills
```

Antigravity loads both the skills and the hooks (from root `hooks.json` inside the bundle).

To update, re-run the install command or update the plugin through `agy plugin`.

## Cursor

Cursor loads local plugins from `~/.cursor/plugins/local/<plugin>/` and rejects symlinks that point outside that directory. Copy the bundle from a local clone:

```bash
mkdir -p ~/.cursor/plugins/local/engineering-skills
cp -R /path/to/skills/plugins/engineering-skills/. ~/.cursor/plugins/local/engineering-skills/
```

Cursor reads `.cursor-plugin/plugin.json`, which loads the skills and sets `"hooks": {}` so Claude Code's hooks stay off.

To update, pull the repository and copy `plugins/engineering-skills/` over the local folder again. To remove, delete `~/.cursor/plugins/local/engineering-skills`.

## Devin

Install the pack subfolder directly with the Devin CLI:

```bash
devin plugins install augments-labs/skills#plugins/engineering-skills
```

Or from a local clone:

```bash
devin plugins install --local /path/to/skills/plugins/engineering-skills
```

Devin reads `.devin-plugin/plugin.json` and discovers `skills/` automatically. The bundled hook adapter detects Devin (`DEVIN_PROJECT_DIR`) and allows calls silently, so Devin gets the skills cleanly without broken hook calls.

## Grok Build

Register the marketplace and install the pack:

```bash
grok plugin marketplace add augments-labs/skills
grok plugin install engineering-skills
```

Grok asks you to trust the plugin before enabling it. Its manifest sets `"hooks": []`, so Grok loads the skills only.

## Kimi Code

Inside Kimi Code, install the repository archive or your local clone path:

```text
/plugins install https://github.com/augments-labs/skills/archive/refs/heads/main.zip
```

Kimi reads `.kimi-plugin/plugin.json` and loads the skills only.

## Muse Code

Add the marketplace and install the pack:

```bash
muse plugins marketplace add augments-labs https://github.com/augments-labs/skills.git
muse plugins install engineering-skills@augments-labs
```

Muse reads `.muse-plugin/plugin.json`, which lists each promoted skill and declares no hooks.

## Hermes

Install the pack subdirectory and enable it:

```bash
hermes plugins install augments-labs/skills/plugins/engineering-skills --enable
```

Hermes scans the bundle before installing and rates it `caution` because the bundled hook scripts mention `sudo` so they can recognize it in shell commands. Hermes never runs those scripts. Confirm at the prompt to finish installing.

## OpenCode 2.x

Add the repository as a Git plugin:

```bash
opencode plugin add git+https://github.com/augments-labs/skills.git
```

OpenCode loads the root `index.js`, which registers the skills from `plugins/engineering-skills/`. Hooks do not run in OpenCode.

## pi

Install from Git:

```bash
pi install git:github.com/augments-labs/skills
```

pi reads the `"pi"` entry in `package.json`, which points directly to `./plugins/engineering-skills/skills`. Hooks do not run in pi.

## Skill-only install (`npx skills add`)

If you want only the `SKILL.md` folders without harness plugins or hooks:

```bash
npx skills add augments-labs/skills/plugins/engineering-skills
```

For any agent not listed above, see [Using the skills on another agent](other-agents.md).
