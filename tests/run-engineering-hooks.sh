#!/usr/bin/env bash
# Offline tests for the engineering hooks (hooks/engineering/). Each case
# feeds a command or edit to the normalized checker, or a harness-shaped
# event to a hook entry script, inside throwaway git repositories with HOME
# pointed at a scratch directory. No harness CLI, no network, no model call.

set -uo pipefail
export LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hooks="$repo/hooks/engineering"
check="$hooks/lib/check.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home" TMPDIR="$tmp/tmpdir"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$TMPDIR"
# Hooks run under the user's bash; on macOS that is /bin/bash 3.2.
B=bash
[ "$(uname -s)" = Darwin ] && [ -x /bin/bash ] && B=/bin/bash
echo "hooks run with $("$B" -c 'echo "$BASH_VERSION"')"
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main
git config --global advice.detachedHead false

pass=0 failed=0
ok() { pass=$((pass + 1)); echo "  ok    $*"; }
bad() { failed=$((failed + 1)); echo "  FAIL  $*"; sed 's/^/        /' "$tmp/err" 2>/dev/null; }

# verdict EXPECTED STATUS DESCRIPTION: allow is exit 0, deny is exit 2.
verdict() {
  local got=other
  [ "$2" -eq 0 ] && got=allow
  [ "$2" -eq 2 ] && got=deny
  # A deny must say why.
  [ "$got" = deny ] && ! grep -q 'blocked this[^:]*: [^ ]' "$tmp/err" && got=deny-without-reason
  if [ "$got" = "$1" ]; then ok "$1: $3"; else bad "expected $1, got $got (exit $2): $3"; fi
}

D=guard-destructive-git
P=guard-protected-branch

sh_case() { # EXPECTED HOOK CWD COMMAND
  "$B" "$check" --hook "$2" --tool shell --cwd "$3" --command "$4" >/dev/null 2>"$tmp/err"
  verdict "$1" $? "$2 [$(basename "$3")] $4"
}
edit_case() { # EXPECTED HOOK CWD PATH
  "$B" "$check" --hook "$2" --tool edit --cwd "$3" --file-path "$4" >/dev/null 2>"$tmp/err"
  verdict "$1" $? "$2 edit $4"
}

jstr() { # JSON string literal for $1
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# hook_io HOOK HARNESS-ARG JSON: runs an entry script; sets rc, out, err.
hook_io() {
  if [ -n "$2" ]; then
    printf '%s' "$3" | "$B" "$hooks/$1.sh" "$2" >"$tmp/out" 2>"$tmp/err"
  else
    printf '%s' "$3" | "$B" "$hooks/$1.sh" >"$tmp/out" 2>"$tmp/err"
  fi
  rc=$?
  out="$(cat "$tmp/out")"
  err="$(cat "$tmp/err")"
}

# ------------------------------------------------------------- fixtures --

r="$tmp/repo"          # on feature branch feat
wm="$tmp/wt-main"      # linked worktree on main
git init -q "$r"
git -C "$r" commit -q --allow-empty -m init
git -C "$r" switch -q -c unmerged
git -C "$r" commit -q --allow-empty -m "only on unmerged"
git -C "$r" switch -q main
git -C "$r" branch merged
git -C "$r" switch -q -c feat
git -C "$r" worktree add -q "$wm" main
printf 'dist/\n' > "$wm/.gitignore"
git init -q --bare "$tmp/origin.git"
git -C "$r" remote add origin "$tmp/origin.git"
git -C "$r" push -q origin main feat 2>/dev/null
outside="$tmp/outside"
mkdir -p "$outside"
policy_dir="$HOME/.config/augments-skills"
policy() { mkdir -p "$policy_dir"; printf '%s\n' "$1" > "$policy_dir/policy.json"; }
no_policy() { rm -rf "$policy_dir"; }

echo "guard-destructive-git: blocked commands"
for c in \
  'git reset --hard' 'git reset --hard HEAD~1' 'git reset --ha' \
  'git push --force origin feat' 'git push -f origin feat' 'git push -fu origin feat' \
  'git push origin +feat' 'git push origin +HEAD:feat' 'git push --mirror origin' \
  'git push --force-with-lease origin main' 'git push --no-verify origin feat' \
  'git clean -fd' 'git clean -df' 'git clean -fdx' 'git clean -f -X' 'git clean --force' \
  'git checkout -- .' 'git checkout HEAD -- .' 'git checkout .' 'git checkout -f main' 'git checkout -- :/' \
  'git switch --discard-changes main' 'git restore .' 'git restore -W -- .' 'git restore --staged --worktree .' \
  'git stash clear' 'git branch -D unmerged' 'git branch -d -f unmerged' 'git branch --delete --force unmerged' \
  'git commit --no-verify -m x' 'git commit -n -m x' 'git commit -anm x' 'git commit --no-veri -m x' \
  'git merge --no-verify feat' 'HUSKY=0 git commit -m x' 'export HUSKY=0' 'HUSKY_SKIP_HOOKS=1 git push' \
  'env HUSKY=0 git commit -m x' 'git -c core.hooksPath=/dev/null commit -m x' \
  'git -c core.hookspath= push origin feat' 'git config core.hooksPath /dev/null' \
  'rm -rf /' 'rm -rf /srv/data' 'rm -fr /srv/data' 'rm -r -f /srv/data' 'rm --recursive --force /srv/data' \
  'rm -rf /tmp/../srv' 'rm -rf /srv/build/x' 'rm -rf "$NO_SUCH_VAR_X/data"' 'rm -rf "$(pwd)/x"' \
  'find . -name "*.o" | xargs rm -rf' 'find . -type d -exec rm -rf {} +' \
  'sudo git reset --hard' 'env -C /srv git reset --hard' 'command git stash clear' 'timeout 5 git reset --hard' \
  'bash -c "git reset --hard"' 'sh -lc "cd /srv && git clean -fd"' 'eval "git stash clear"' \
  'echo "git reset --hard" | bash' 'bash <<< "git stash clear"' \
  'git status && git reset --hard' 'true; (git stash clear)' 'git -C "$HOME" reset --hard'
do sh_case deny $D "$r" "$c"; done
sh_case deny $D "$r" 'sh <<EOF
git stash clear
EOF'

echo "guard-destructive-git: allowed commands"
for c in \
  'git status' 'git reset --soft HEAD~1' 'git reset HEAD file' 'git push origin feat' \
  'git push --force-with-lease origin feat' 'git push --force-with-lease' 'git push --dry-run --force origin feat' \
  'git clean -n' 'git clean -nd' 'git checkout feat' 'git checkout -b topic' 'git checkout -- src/a.js' \
  'git restore src/a.js' 'git restore --staged .' 'git stash' 'git stash drop' 'git branch -D merged' \
  'git branch -D no-such-branch' 'git branch -dr origin/feat' 'git commit -m x' 'git commit -am "-n"' \
  'git commit -m "fix: git push --force docs"' 'git commit -m "skip --no-verify talk"' \
  'git log --grep="reset --hard"' 'grep -rn "git reset --hard" .' 'rg -- "--no-verify"' \
  'echo "rm -rf /"' "printf '%s\\n' 'git stash clear'" 'HUSKY=1 git commit -m x' \
  'git config --get core.hooksPath' 'git config --unset core.hooksPath' \
  'rm -rf node_modules' 'rm -rf ./dist/' 'rm -rf build target .next coverage' 'rm -rf pkg/foo.egg-info' \
  'rm -rf /tmp/scratch' 'rm -rf "$TMPDIR/cache"' 'rm -rf src/__pycache__' 'rm -r docs' 'rm -f notes.txt' \
  'cd /tmp && rm -rf work' 'cat <<EOF
git stash clear
EOF' 'git commit -m "$(cat <<'"'"'EOF'"'"'
feat: x

Never use --no-verify or git reset --hard.
EOF
)"'
do sh_case allow $D "$r" "$c"; done
sh_case allow $D "$r" 'git -c core.hooksPath=.githooks status'

echo "guard-destructive-git: --force-with-lease policy"
policy '{"forceWithLease": "block"}'
sh_case deny $D "$r" 'git push --force-with-lease origin feat'
no_policy
sh_case allow $D "$r" 'git push --force-with-lease origin feat'

echo "guard-protected-branch: commands"
sh_case deny $P "$wm" 'git commit -m x'
sh_case deny $P "$wm" 'git commit --amend --no-edit'
sh_case deny $P "$wm" 'git merge feat'
sh_case deny $P "$wm" 'git cherry-pick feat'
sh_case deny $P "$wm" 'git revert HEAD'
sh_case deny $P "$wm" 'git am patch.mbox'
sh_case deny $P "$wm" 'git push'
sh_case deny $P "$wm" 'git push origin main'
sh_case deny $P "$r" 'git push origin main'
sh_case deny $P "$r" 'git push origin HEAD:main'
sh_case deny $P "$r" 'git push origin feat:refs/heads/main'
sh_case deny $P "$r" 'git push origin --delete main'
sh_case deny $P "$r" 'git push origin :master'
sh_case deny $P "$r" 'git push origin "refs/heads/*:refs/heads/*"'
sh_case deny $P "$r" 'git push --all origin'
sh_case deny $P "$r" 'git -C ../wt-main commit -m x'
sh_case deny $P "$r" "git -C '$wm' commit -m x"
sh_case deny $P "$r" 'cd ../wt-main && git commit -m x'
sh_case deny $P "$r" 'git switch main && git commit -m x'
sh_case allow $P "$r" 'git commit -m x'
sh_case allow $P "$r" 'git push origin feat'
sh_case allow $P "$r" 'git push'
sh_case allow $P "$r" 'git push origin main --dry-run'
sh_case allow $P "$r" 'git push origin v1.0 tag v2.0'
sh_case allow $P "$wm" 'git -C ../repo commit -m x'
sh_case allow $P "$wm" 'git status'
sh_case allow $P "$wm" 'git pull --ff-only'
sh_case allow $P "$wm" 'git merge --ff-only feat'
sh_case allow $P "$wm" 'git merge --abort'
sh_case allow $P "$wm" 'git commit --dry-run'
sh_case allow $P "$wm" 'git cherry-pick --abort'
sh_case allow $P "$wm" 'git switch -c topic'
sh_case deny $P "$wm" 'git commit -m "push to main"; git switch -c x'
sh_case allow $P "$wm" 'git switch -c topic2 && git commit -m x'
sh_case allow $P "$wm" 'git checkout -b topic3 && git commit -m x'
sh_case allow $P "$wm" 'git checkout -btopic4 && git push origin topic4'
sh_case allow $P "$wm" 'git switch --detach && git commit -m x'
sh_case allow $P "$wm" 'git switch feat && git commit -m x'
sh_case deny $P "$wm" 'git checkout -- a.txt && git commit -m x'
sh_case deny $P "$wm" 'git checkout no-such-path && git commit -m x'
sh_case deny $P "$r" 'git switch -c t5 && git switch main && git commit -m x'
sh_case deny $P "$r" 'git switch -c t6 && git -C ../wt-main commit -m x'
sh_case deny $P "$r" 'git checkout main && git push'

echo "guard-protected-branch: edits"
edit_case deny $P "$wm" "$wm/src/a.js"
edit_case deny $P "$wm" "src/new/deep/file.js"
edit_case deny $P "$r" "../wt-main/README.md"
edit_case allow $P "$wm" "$wm/dist/bundle.js"
edit_case allow $P "$r" "$r/src/a.js"
edit_case allow $P "$wm" "$outside/notes.md"
git -C "$r" worktree add -q --detach "$tmp/wt-detached" main
edit_case allow $P "$tmp/wt-detached" "$tmp/wt-detached/a.js"

echo "guard-protected-branch: repository-local list adds branches but grants nothing"
printf '%s\n' '{"protectedBranches": ["release/*"], "disabledHooks": ["guard-protected-branch"], "protectedBranchExemptRepos": ["."]}' > "$wm/.augments-labs-config.json"
sh_case deny $P "$wm" 'git commit -m x'
git -C "$r" worktree add -q -b release/1.0 "$tmp/wt-release" main
cp "$wm/.augments-labs-config.json" "$tmp/wt-release/"
sh_case deny $P "$tmp/wt-release" 'git commit -m x'
sh_case allow $P "$r" 'git commit -m x'
printf 'not json' > "$wm/.augments-labs-config.json"
sh_case deny $P "$wm" 'git commit -m x'
grep -q 'ignoring malformed' "$tmp/err" && ok "malformed .augments-labs-config.json is reported" || bad "malformed .augments-labs-config.json not reported"
rm -f "$wm/.augments-labs-config.json"

echo "policy.json bypasses (user-global only)"
policy '{"disabledHooks": ["guard-protected-branch"]}'
sh_case allow $P "$wm" 'git commit -m x'
edit_case allow $P "$wm" "$wm/src/a.js"
sh_case deny $D "$wm" 'git reset --hard'
policy "{\"protectedBranchExemptRepos\": [$(jstr "$r")]}"
sh_case allow $P "$wm" 'git commit -m x'
sh_case allow $P "$r" 'git push origin main'
policy '{"protectedBranchExemptRepos": ["~/../repo/"]}'
sh_case allow $P "$wm" 'git commit -m x'
policy "{\"protectedBranchExemptRepos\": [$(jstr "$outside")]}"
sh_case deny $P "$wm" 'git commit -m x'
policy '{"protectedBranches": ["feat"]}'
sh_case deny $P "$r" 'git commit -m x'
policy '{"disabledHooks": ["guard-destructive-git"]}'
sh_case allow $D "$r" 'git reset --hard'
policy '{"disabledHooks": ['
sh_case deny $D "$r" 'git reset --hard'
grep -q 'ignoring malformed' "$tmp/err" && ok "malformed policy.json is reported and grants nothing" || bad "malformed policy.json not reported"
no_policy

echo "policy directory is off limits to agents, even with both hooks disabled"
policy '{"disabledHooks": ["guard-destructive-git", "guard-protected-branch"]}'
for h in $D $P; do
  for c in \
    'echo "{}" > ~/.config/augments-skills/policy.json' 'printf x >> "$HOME/.config/augments-skills/policy.json"' \
    'tee ~/.config/augments-skills/policy.json < /dev/null' 'rm -rf ~/.config' 'rm ~/.config/augments-skills/policy.json' \
    'mv /dev/null ~/.config/augments-skills/policy.json' 'cp x.json ~/.config/augments-skills/' \
    'python3 -c "1" ~/.config/augments-skills/policy.json' 'sed -i s/a/b/ ~/.config/augments-skills/policy.json' \
    'cd ~/.config/augments-skills && touch x' 'bash -c "echo > ~/.config/augments-skills/config.json"' \
    "echo x > '$policy_dir/policy.json'" 'mkdir -p ~/.config/augments-skills' 'rm -rf ~/.config/augments-*'
  do sh_case deny $h "$r" "$c"; done
  for c in \
    'cat ~/.config/augments-skills/policy.json' 'ls -la ~/.config/augments-skills' \
    'jq . ~/.config/augments-skills/policy.json' 'git commit -m "docs: explain ~/.config/augments-skills/policy.json"' \
    'grep -r augments-skills ~/.config/augments-skills'
  do sh_case allow $h "$r" "$c"; done
  edit_case deny $h "$r" "$policy_dir/policy.json"
  edit_case deny $h "$r" "~/.config/augments-skills/new.json"
  edit_case deny $h "$r" "$HOME/.config"
done
ln -s "$policy_dir" "$tmp/policy-link" 2>/dev/null
if [ -L "$tmp/policy-link" ]; then
  sh_case deny $D "$r" "echo x > '$tmp/policy-link/policy.json'"
  edit_case deny $D "$r" "$tmp/policy-link/policy.json"
else
  echo "  skip  symlinks unavailable on this platform"
fi
no_policy

echo "harness adapters"
ev_cc() { printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":%s,"tool_input":{"command":%s}}' "$(jstr "$1")" "$(jstr "$2")"; }
hook_io $D claude-code "$(ev_cc "$r" 'git reset --hard')"
[ "$rc" -eq 2 ] && [ -z "$out" ] && case "$err" in *"$D blocked this command: git reset --hard"*) true ;; *) false ;; esac &&
  ok "claude-code: deny is exit 2 with the reason on stderr" || bad "claude-code deny contract (rc=$rc out=$out err=$err)"
hook_io $D claude-code "$(ev_cc "$r" 'git status')"
[ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] && ok "claude-code: allow is a silent exit 0" || bad "claude-code allow contract (rc=$rc)"
hook_io $P claude-code "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",\"cwd\":$(jstr "$wm"),\"tool_input\":{\"file_path\":$(jstr "$wm/a.txt"),\"old_string\":\"git reset --hard\"}}"
[ "$rc" -eq 2 ] && ok "claude-code: Edit on a protected branch is denied" || bad "claude-code Edit on main (rc=$rc)"
hook_io $D claude-code "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":$(jstr "$r"),\"tool_input\":{\"file_path\":\"a.txt\",\"content\":\"git reset --hard\"}}"
[ "$rc" -eq 0 ] && ok "claude-code: file content is not mistaken for a command" || bad "claude-code Write content (rc=$rc)"
hook_io $P claude-code "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"NotebookEdit\",\"cwd\":$(jstr "$wm"),\"tool_input\":{\"notebook_path\":$(jstr "$wm/n.ipynb")}}"
[ "$rc" -eq 2 ] && ok "claude-code: NotebookEdit path is checked" || bad "claude-code NotebookEdit (rc=$rc)"
hook_io $D "" "$(ev_cc "$r" 'git stash clear')"
[ "$rc" -eq 2 ] && ok "no harness argument: Claude Code shape is detected" || bad "harness detection, claude-code (rc=$rc)"
hook_io $D claude-code "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git reset --hard\"}}"
[ "$rc" -eq 0 ] && ok "events other than PreToolUse pass through" || bad "PostToolUse (rc=$rc)"
hook_io $D claude-code '{"tool_name": "Bash", "tool_input": {"command": "git reset --ha'
[ "$rc" -eq 0 ] && case "$err" in *"could not parse"*) true ;; *) false ;; esac &&
  ok "unparseable input fails open with a note" || bad "unparseable input (rc=$rc err=$err)"

hook_io $D codex "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"exec_command\",\"cwd\":$(jstr "$r"),\"tool_input\":{\"command\":[\"bash\",\"-lc\",\"git reset --hard\"]}}"
[ "$rc" -eq 2 ] && ok "codex: array command is joined and walked" || bad "codex array command (rc=$rc)"
hook_io $D codex "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"shell\",\"cwd\":$(jstr "$r"),\"tool_input\":{\"command\":[\"git\",\"commit\",\"-m\",\"it's --no-verify\"]}}"
[ "$rc" -eq 0 ] && ok "codex: array arguments keep their quoting" || bad "codex array quoting (rc=$rc)"
hook_io $P codex "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"exec_command\",\"cwd\":$(jstr "$r"),\"tool_input\":{\"cmd\":\"git commit -m x\",\"workdir\":$(jstr "$wm")}}"
[ "$rc" -eq 2 ] && ok "codex: cmd and workdir are honored" || bad "codex cmd/workdir (rc=$rc)"
patch='*** Begin Patch
*** Update File: src/app.js
@@
-a
+b
*** End Patch'
hook_io $P codex "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"apply_patch\",\"cwd\":$(jstr "$wm"),\"tool_input\":{\"input\":$(jstr "$patch")}}"
[ "$rc" -eq 2 ] && ok "codex: apply_patch file headers are checked" || bad "codex apply_patch (rc=$rc)"
hook_io $P codex "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"shell\",\"cwd\":$(jstr "$wm"),\"tool_input\":{\"command\":[\"apply_patch\",$(jstr "$patch")]}}"
[ "$rc" -eq 2 ] && ok "codex: apply_patch inside a shell command is checked" || bad "codex shell apply_patch (rc=$rc)"
hook_io $P codex "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"apply_patch\",\"cwd\":$(jstr "$r"),\"tool_input\":{\"input\":$(jstr "$patch")}}"
[ "$rc" -eq 0 ] && ok "codex: apply_patch on a feature branch is allowed" || bad "codex apply_patch on feat (rc=$rc)"

ev_ag() { printf '{"hookEventName":"PreToolUse","cwd":%s,"toolCall":{"name":"run_command","args":{"CommandLine":%s,"Cwd":%s}}}' "$(jstr "$1")" "$(jstr "$2")" "$(jstr "$1")"; }
hook_io $D antigravity "$(ev_ag "$r" 'git reset --hard')"
[ "$rc" -eq 0 ] && case "$out" in '{"decision":"deny","reason":"'"$D"' blocked this command: '*'"}') true ;; *) false ;; esac &&
  ok "antigravity: deny is a JSON decision on stdout, exit 0" || bad "antigravity deny contract (rc=$rc out=$out)"
hook_io $D antigravity "$(ev_ag "$r" 'git status')"
[ "$rc" -eq 0 ] && [ "$out" = '{}' ] && ok "antigravity: allow is {} (never an explicit allow)" || bad "antigravity allow contract (out=$out)"
hook_io $P "" "$(ev_ag "$wm" 'git commit -m "say \"hi\""')"
[ "$rc" -eq 0 ] && case "$out" in *'"decision":"deny"'*) true ;; *) false ;; esac &&
  ok "no harness argument: Antigravity shape is detected" || bad "harness detection, antigravity (out=$out)"
hook_io $P antigravity "{\"hookEventName\":\"PreToolUse\",\"cwd\":$(jstr "$wm"),\"toolCall\":{\"name\":\"write_to_file\",\"args\":{\"TargetFile\":$(jstr "$wm/x.md"),\"CodeContent\":\"hi\"}}}"
case "$out" in *'"decision":"deny"'*) ok "antigravity: write_to_file target is checked" ;; *) bad "antigravity write_to_file (out=$out)" ;; esac
hook_io $D antigravity "{\"hookEventName\":\"PreToolUse\",\"cwd\":$(jstr "$r"),\"toolCall\":{\"name\":\"replace_file_content\",\"args\":{\"TargetFile\":$(jstr "$policy_dir/policy.json")}}}"
case "$out" in *'"decision":"deny"'*) ok "antigravity: edits to the policy file are denied" ;; *) bad "antigravity policy edit (out=$out)" ;; esac
hook_io $D antigravity 'not json'
[ "$rc" -eq 0 ] && [ "$out" = '{}' ] && ok "antigravity: unparseable input fails open" || bad "antigravity unparseable (out=$out)"
hook_io $D bogus "$(ev_cc "$r" 'git status')"
[ "$rc" -eq 64 ] && ok "unknown harness argument is a usage error" || bad "unknown harness (rc=$rc)"

echo "push.default=upstream pushes to the upstream's name"
git -C "$r" worktree add -q -b topic "$tmp/wt-topic" main
git -C "$r" config branch.topic.remote origin
git -C "$r" config branch.topic.merge refs/heads/main
git -C "$r" fetch -q origin
git -C "$r" config push.default upstream
sh_case deny $P "$tmp/wt-topic" 'git push'
git -C "$r" config --unset push.default

echo
echo "run-engineering-hooks: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
