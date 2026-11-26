# Engineering hooks

The `engineering-skills` plugin ships two hooks that run before your agent calls a tool. They block a short list of commands and edits that are hard to undo, and they tell the agent why. When a call is blocked, the agent is instructed to ask you so you can decide whether to run it yourself.

The hooks run in Claude Code, Codex CLI, and Antigravity when you install the plugin through the harness. Every other supported install gives you the skills only:

- Cursor, Grok Build, Kimi Code, and Muse Code never load the hooks because their manifests declare none.
- Devin loads plugin hook files using its own tool schema, so the hook adapter detects Devin and steps aside silently.
- pi, Hermes, OpenCode, and `npx skills add` load skills only.

The hooks need `bash` and `git` on your `PATH`. On Windows, that means Git for Windows (Git Bash).

## `guard-destructive-git`

Blocks commands that destroy work you have not saved elsewhere, or that skip your repository's git hooks:

- `git reset --hard`
- forced pushes: `git push --force`, `-f`, `+refspec`, and `--mirror`
- `git push --force-with-lease` to a protected branch, or with `--all`
- `git clean -f` in any form (`-fd`, `-fdx`), and `git clean` when `clean.requireForce` is off
- `git checkout -- .`, `git checkout HEAD -- .`, `git restore .`, and the same for `:/`, `..`, or `*`
- `git checkout -f` and `git switch --discard-changes`
- `git stash clear`
- `git branch -D` on a branch with commits that are in neither `HEAD` nor the branch's upstream
- skipped hooks: `--no-verify` and `-n` on `git commit`, `--no-verify` on `git merge` and `git push`, `HUSKY=0`, `HUSKY_SKIP_HOOKS`, and `core.hooksPath` set with `git -c` or `git config`
- `rm -rf` (any spelling of recursive plus force) outside your temporary directory and build caches, and `rm -rf` on paths chosen at run time (`xargs`, `find -exec`)

These stay allowed:

- dry runs: `git clean -n` and `git push --dry-run`
- `git push --force-with-lease` to your own feature branch
- `git restore --staged`, `git checkout <branch>`, and restoring single files
- `git branch -D` on a branch that is already merged
- `rm -rf` inside `$TMPDIR`, `/tmp`, or `/var/tmp`, and on build caches below the current directory (`node_modules`, `dist`, `build`, `target`, `.next`, `coverage`, `__pycache__`, `*.egg-info`, and similar)

## `guard-protected-branch`

Blocks direct work on a protected branch:

- `git commit`, `git merge`, `git cherry-pick`, `git revert`, and `git am` while a protected branch is checked out
- `git push` to a protected branch, including `HEAD:main`, `refs/heads/main`, deletes, and `--all` or `--mirror`
- edits to files in a work tree that has a protected branch checked out (files that git ignores are still allowed)

These stay allowed: `--dry-run`, `git merge --ff-only`, `--abort`, `--quit`, `--skip`, and `--no-commit`.

The hook checks the branch of the work tree the command actually touches. A command run with `git -C <path>`, after `cd`, or against a linked worktree is judged by that worktree's branch, and `git switch -c topic && git commit` is judged by `topic`.

### Protected branches

`main` and `master` are always protected. To protect more branches in one repository, commit a `.augments-labs-config.json` file at its root:

```json
{ "protectedBranches": ["develop", "release/*"] }
```

Names are shell-style patterns. This file can only add protection. Anything else in it, such as a bypass, is ignored because an agent can edit files inside the repository.

## Turning a hook off or exempting a repository

Bypasses live only in `~/.config/augments-skills/policy.json`, outside every repository. Create and edit it yourself. Both hooks block agents from writing anywhere under `~/.config/augments-skills/`, even when you have turned a hook off.

```json
{
  "disabledHooks": ["guard-protected-branch"],
  "protectedBranchExemptRepos": ["~/code/scratch-repo"],
  "protectedBranches": ["production"],
  "forceWithLease": "block"
}
```

Every key is optional:

| Key | Effect |
| --- | --- |
| `disabledHooks` | Hook names to turn off everywhere: `guard-destructive-git`, `guard-protected-branch`. |
| `protectedBranchExemptRepos` | Repositories where `guard-protected-branch` allows work on protected branches. Use the path of the repository's main work tree or of a linked worktree (`~` is expanded). |
| `protectedBranches` | Branch patterns to protect in every repository. |
| `forceWithLease` | `"block"` blocks `git push --force-with-lease` everywhere. By default it is allowed on branches that are not protected. |

If the file is not valid JSON, the hooks print a note and ignore it, so a broken file never grants a bypass.

## Codex: trust the hooks once

Codex does not run a plugin's hooks until you trust them. After you install or update `engineering-skills`, Codex shows "Hooks need review" at the start of a session. Choose to trust them. If you continue without trusting them, nothing is enforced. Codex asks again whenever an update changes the hook files.

## Limits

The hooks read the command your agent is about to run; they do not execute it. They follow `&&`, `;`, pipes, subshells, `bash -c`, `eval`, `sudo`, `env`, `xargs`, and shell scripts fed through a heredoc or a pipe. They do not read script files the command runs (`bash ./script.sh`) or code passed to other interpreters. If a hook cannot parse the event it receives, it allows the call and prints a note. Treat the hooks as a guard rail against mistakes, not as a sandbox.
