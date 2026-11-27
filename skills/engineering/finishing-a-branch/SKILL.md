---
name: finishing-a-branch
description: "Finishes a branch safely: pushing, opening or describing a pull request, merging, squashing or rewriting history, and deleting branches or worktrees. Load it before the first git command when asked to finish, ship, wrap up, merge, or clean up a branch. Skip it for plain commits, creating branches, and questions about git."
---

# Finishing a branch

Finishing is where work gets lost: a force push erases a teammate's commit,
a branch delete takes the only copy of a spike, a merge lands on a branch
nobody asked you to touch. Look at the real state first, then do only what
was asked.

## 1. Read the live state

Before any push, merge, rewrite, or delete, run read-only commands and look:

- `git status` and `git stash list`: uncommitted or stashed work.
- `git fetch` (it changes no branch), then `git branch -vv`: what is ahead,
  behind, or gone on the remote.
- `git log --oneline <remote>/<branch>..<branch>` and the reverse: commits
  only you have, and commits only the remote has.
- `git worktree list`, and `git -C <path> status` for each worktree.

Decide from this output, not from memory or from the task description.

## 2. Green checks are not permission

Passing tests or CI tell you the code works. They do not tell you to push,
open a PR, merge, or delete anything. Do the transitions the user named.
When "finish" or "ship" is ambiguous, the safe default is to push the
branch itself and stop; merging into a shared or default branch, or
deleting, waits for the user to say so.

## 3. Rewriting published history

A branch is published once it exists on a remote. Before you rebase,
squash, amend, or reset it:

- A rejected push means the remote moved. Fetch and integrate; it is never
  a reason to force.
- Fetch, and check whether the remote has commits you do not. If it does,
  someone else is working there: integrate their commits or stop and ask.
  Never drop them.
- Push with `--force-with-lease` naming the exact commit you last saw,
  never plain `--force`.
- If the user asked only for a squash, a rewrite they did not mention (like
  rebasing onto a newer main) needs its own yes.

## 4. Deleting branches and worktrees

Delete only what provably exists elsewhere:

- Use `git branch -d`, which refuses unmerged branches. If it refuses,
  list the commits that would be lost (`git log --oneline <branch>
  --not --remotes --branches=<others>`) and ask; do not switch to `-D`.
- A branch whose upstream is gone or was never pushed is the only copy.
- Before deleting a remote branch, fetch and compare: commits there that
  you never saw are someone else's work. Ask before deleting them.
- Remove a worktree only after `git -C <path> status --ignored` is clean.
  `git worktree remove` deletes ignored files without asking, so notes or
  local config there are lost. If anything shows, keep the worktree and say
  what is there; never `--force` it away.
- After cleaning up, list what you removed and what you kept, and why.

## 5. Pull request descriptions

When the repository has a PR template, fill every section, in order, from
evidence:

- Run the tests on the branch head and tick "tests pass" only if they did.
  If some fail, say which.
- List breaking changes from the diff against the base (`git diff
  <base>...HEAD`): removed or renamed public functions, fields, formats,
  and columns. Write "None" only after you looked.
- Do not claim review, manual testing, or checks you did not do.

## 6. Report

End with the branch, its head commit, what you pushed or changed where, and
anything you left for the user to decide.
