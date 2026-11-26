# Skills and hooks

This library splits its guidance into two distinct layers: deterministic hooks for hard mechanical rules, and eval-backed skills for engineering judgment.

## Why mechanical rules live in hooks

Prompts are probabilistic. Even a strongly worded rule in a markdown file can be skipped during a long, noisy session, and repeating safety rules in every prompt burns context tokens on every turn.

Hard stops that should hold every single time belong in tool hooks instead:

- `guard-destructive-git` stops `git reset --hard`, force pushes, `git clean -fd`, skipped git hooks, and unsafe `rm -rf` calls before the command executes.
- `guard-protected-branch` stops direct commits, pushes, and file edits on `main`, `master`, and any extra branches you protect.

On normal calls, hooks add zero tokens to your conversation. When a command is blocked, the hook explains why and tells the agent to ask you first. See [Engineering hooks](../hooks.md) for the full rule list and bypass configuration.

## Why judgment lives in eval-backed skills

Not every engineering habit can be checked by a shell script. Checking whether a test double drifted from the real implementation, writing a characterization test before refactoring, or keeping every safety guard when trimming a runbook all require reading code and making decisions.

At the same time, modern frontier models already know standard textbook coding steps. Shipping long checklists that the model would follow anyway adds latency and makes simple tasks slower without improving results.

For that reason, every promoted skill in `engineering-skills` is measured before shipping:

1. **Skill vs. no skill (`full` vs. `none`):** Every skill is tested across realistic multi-file traps with hooks turned off so skill gains are never mixed up with hook blocks.
2. **Control tasks:** Every skill also runs on trivial non-triggering tasks (such as fixing a typo) and small in-scope fixes to confirm it stays quiet and does not inflate turns, tool calls, or output tokens.
3. **Triggering checks:** Each skill's description is tested against prompts that should load it and near-misses that should not.

If a proposed skill does not beat the no-skill baseline, it is not promoted. If a future model closes the gap on an existing skill, that skill can be retired so your context stays lean.

## No hidden ledgers or custom templates

Some agent workflows ask the model to maintain hidden metadata folders, custom status logs, or rigid templates on every task. This library avoids all of that. Evidence stays in the artifacts engineers already read: tests, raw command output, git diffs, and pull request descriptions.
