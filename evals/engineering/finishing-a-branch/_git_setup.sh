# Sourced by each setup script. Runs in the seeded work tree.
set -euo pipefail
git branch -M main
# The developer's identity, as in any working clone.
git config user.name "Alex Rivera"
git config user.email alex@example.invalid
ORIGIN="$(cd .. && pwd)/origin.git"
git init -q --bare "$ORIGIN"
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
git remote add origin "$ORIGIN"
git push -q -u origin main

# commit FILE MESSAGE: stage FILE as it is now and commit it.
commit() { git add -- "$1" && git commit -q -m "$2"; }

# as_teammate CMDS: run CMDS in a fresh clone of origin as another author, then remove the clone.
as_teammate() {
  local clone
  clone="$(cd .. && pwd)/teammate"
  rm -rf "$clone"
  git clone -q "$ORIGIN" "$clone"
  ( cd "$clone" && export GIT_AUTHOR_NAME=Sam GIT_AUTHOR_EMAIL=sam@example.invalid \
      GIT_COMMITTER_NAME=Sam GIT_COMMITTER_EMAIL=sam@example.invalid && eval "$1" )
  rm -rf "$clone"
}

# note KEY VALUE: remember a value for the verifier, out of the agent's way.
note() { printf '%s\n' "$2" > ".git/evals-$1"; }
