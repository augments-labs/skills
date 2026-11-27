# Finishing a branch

The `finishing-a-branch` skill makes your agent look at the real state of your repository and remote before it pushes, merges, rewrites, or deletes anything, and then do only what you asked. Finishing is where work most often gets lost: a force push that erases a teammate's commit, a branch delete that takes the only copy of an experiment, or a worktree removal that takes your notes with it.

## When it loads (and when it skips)

`finishing-a-branch` loads before the first git command when you ask your agent to finish, ship, wrap up, merge, or clean up a branch. That covers pushing, opening or describing a pull request, merging, squashing or rewriting history, and deleting branches or worktrees.

It skips:

- Plain commits, such as "commit the staged change".
- Creating a branch.
- Questions about git that change nothing.

## What the agent does differently

1. **Reads the live state first.** Before any push, merge, rewrite, or delete, the agent fetches and looks at what is ahead, behind, or gone on the remote, what is uncommitted or stashed, and what each worktree holds. It decides from that output, not from memory.
2. **Treats green checks as no permission.** Passing tests say the code works. They do not tell the agent to merge into a shared branch or delete anything. When "finish it" is ambiguous, the agent pushes the branch itself and stops.
3. **Never forces over commits it has not seen.** A rejected push means someone else pushed. The agent fetches and integrates their work instead of forcing, and when it does rewrite a published branch, it uses `--force-with-lease` pinned to the commit it last saw.
4. **Deletes only what exists elsewhere.** The agent uses `git branch -d`, which refuses unmerged branches, and lists the commits that would be lost instead of switching to `-D`. Before deleting a remote branch, it fetches and checks for commits you never saw.
5. **Keeps worktrees that hold work.** `git worktree remove` deletes ignored files without warning, so the agent checks `git status --ignored` first. If notes, local config, or uncommitted changes are there, it keeps the worktree and tells you what it found.
6. **Fills your PR template from evidence.** The agent runs the tests on the branch head and ticks "tests pass" only if they did, and it lists breaking changes from the diff against the base.

## What stays up to you

- Merging into `main` or any other shared branch.
- Deleting a branch or remote branch that holds commits found nowhere else.
- Removing a worktree that still holds files.
- Rewriting a published branch beyond what you asked for.

## Example prompts

```text
I'm done with this branch and the tests are green. Finish it up.
```

```text
Squash the commits on this branch into one and push it, so it's ready for review.
```

```text
We're done with the old branches. Clean up the local branches and worktrees we don't need anymore.
```
