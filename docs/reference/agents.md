# Supported agents

`engineering-skills` ships manifests for 11 coding agent harnesses plus flat skill folders for `npx skills add`. Every harness reads from the generated bundle under `plugins/engineering-skills/` (or a root entry point that delegates directly to it).

## Compatibility matrix

| Harness | Install entry | Skills | Hooks | Notes |
| --- | --- | --- | --- | --- |
| Claude Code | `.claude-plugin/marketplace.json` -> `plugins/engineering-skills/` | Yes | Yes (`hooks/hooks.json`) | Marketplace catalog at repo root; `plugin.json` lives inside `plugins/engineering-skills/.claude-plugin/` |
| Codex CLI | `.agents/plugins/marketplace.json` -> `plugins/engineering-skills/` | Yes | Yes (`hooks/codex-hooks.json`) | Prompts you to trust hooks on first install and after hook updates |
| Antigravity | `plugins/engineering-skills/.antigravity-plugin/plugin.json` | Yes | Yes (root `hooks.json`) | Reads `skills/` and `hooks.json` directly from the plugin folder |
| Cursor | `plugins/engineering-skills/.cursor-plugin/plugin.json` | Yes | No (`"hooks": {}`) | Copy bundle into `~/.cursor/plugins/local/engineering-skills/`; symlinks outside that folder are rejected |
| Devin | `plugins/engineering-skills/.devin-plugin/plugin.json` | Yes | No (adapter stays inert) | Install via `devin plugins install augments-labs/skills#plugins/engineering-skills`; hook adapter steps aside when `DEVIN_PROJECT_DIR` is set |
| Grok Build | `.grok-plugin/marketplace.json` -> `plugins/engineering-skills/` | Yes | No (`"hooks": []`) | Prompts to trust the plugin; root `.grok-plugin/plugin.json` scopes root installs to `plugins/engineering-skills/skills/` |
| Kimi Code | Root `.kimi-plugin/plugin.json` or bundle `.kimi-plugin/plugin.json` | Yes | No | Installs from zip URL or local clone via `/plugins install`; lists skills only |
| Muse Code | `.claude-plugin/marketplace.json` -> `plugins/engineering-skills/.muse-plugin/plugin.json` | Yes | No | Native manifest lists each skill explicitly under `capabilities.skills` |
| Hermes | `plugins/engineering-skills/plugin.yaml` + `__init__.py` | Yes | No | Installs the `plugins/engineering-skills` subdirectory; install scan flags `caution` because unused hook scripts mention `sudo` |
| OpenCode 2.x | Root `index.js` -> `plugins/engineering-skills/index.js` | Yes | No | Installs from Git URL via `opencode plugin add git+https://...`; zero npm dependencies |
| pi | Root `package.json` (`pi.skills`) -> `plugins/engineering-skills/skills` | Yes | No | Installs from Git via `pi install git:github.com/augments-labs/skills` |
| `npx skills add` | `plugins/engineering-skills/skills/<name>/SKILL.md` | Yes | No | Flat skill folders only |

## Why hooks run on three harnesses today

Hook event payloads, tool names, and block protocols vary widely across harnesses. Claude Code (`Bash`/`Edit`/`Write` with exit code 2), Codex CLI (`apply_patch` and shell commands), and Antigravity (`run_command`/file tools with JSON `{"decision":"deny"}`) each have dedicated, tested adapters in `hooks/engineering/`.

For the remaining harnesses, the bundle either disables hook loading in the manifest (`Cursor`, `Grok Build`, `Kimi Code`, `Muse Code`), loads skills only (`Hermes`, `OpenCode 2.x`, `pi`, `npx skills add`), or detects the harness in the adapter and exits cleanly (`Devin`) so users never hit broken hook executions.

See [Installing, updating, and removing](../guides/installing.md) for exact install commands and [Engineering hooks](../hooks.md) for hook rules and bypasses.
