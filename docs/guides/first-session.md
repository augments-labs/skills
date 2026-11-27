# Your first session

After installing `engineering-skills`, take two minutes in a throwaway or ordinary repo to confirm that your agent sees the skills and, on hook-enabled harnesses, enforces the git guardrails.

## 1. Check that the skills are visible

Start a fresh session in your agent and ask:

```text
Which engineering skills do you have available right now?
```

You should see the five promoted skills in `engineering-skills`:

- `changing-a-live-schema`
- `debugging`
- `finishing-a-branch`
- `test-driven-development`
- `writing-skills`

If none appear, restart the agent session so it reloads installed plugins, and check [Installing, updating, and removing](installing.md) for any harness-specific trust prompt (such as Codex's hook trust prompt or Grok's plugin trust prompt).

## 2. Check that small tasks stay quiet

Try a trivial prompt in a repo:

```text
Fix the typo "recieve" in README.md.
```

None of the five skills should load. The agent should just make the one-line edit and stop. Keeping small edits free of extra steps is a core goal of the pack.

## 3. Try a real skill trigger

Ask for something that belongs to one of the skills, or invoke a skill by name:

- For a bug with an unknown cause: `"tests/test_billing.py fails after the latest merge and I am not sure why. Track down the cause and fix it."` (loads `debugging`)
- For a new behavior with several rules or a refactor: `"Add pagination to list_products with page and page_size bounds, and write tests first."` (loads `test-driven-development`)
- For a schema change on a live database: `"Rename the fullname column on users to display_name and update the code to match."` (loads `changing-a-live-schema`)
- For wrapping up work: `"I'm done with this branch and the tests are green. Finish it up."` (loads `finishing-a-branch`)
- For a team skill: `"Turn docs/deploy-runbook.md into a project skill under .agents/skills/."` (loads `writing-skills`)

## 4. Check the hooks (Claude Code, Codex CLI, Antigravity)

On Claude Code, Codex CLI, and Antigravity, the two guardrail hooks run automatically before tool calls:

- If your agent tries a destructive git command like `git reset --hard`, `guard-destructive-git` blocks the command and tells the agent to ask you first.
- If you are sitting on `main` or `master` and ask the agent to edit a tracked file or commit, `guard-protected-branch` blocks the call and tells the agent to work on a branch or ask you.

If you want to customize protected branches for a repository or exempt a scratch repo on your machine, see [Engineering hooks](../hooks.md).
