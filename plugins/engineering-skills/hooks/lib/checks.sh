# Check logic for the engineering hooks. Sourced, never executed.
# Needs common.sh, walk.sh, and git.sh. Every check returns 0 to allow, or
# 1 with AUG_REASON set to deny.

aug_deny() { AUG_REASON="$1"; return 1; }

# ------------------------------------------- policy directory (both hooks) --

# Commands that only read their arguments. Redirections are checked apart.
AUG_READONLY=" cat less more head tail ls stat file wc grep egrep fgrep rg jq test [ readlink realpath diff cmp md5sum sha1sum sha256sum sha512sum shasum cksum b2sum echo printf basename dirname pwd true false cd pushd popd type which "

aug_cmd_readonly() {
  case "$AUG_READONLY" in *" $AW_CMD "*) return 0 ;; esac
  return 1
}

# Free text that may mention the policy directory without writing to it:
# commit, tag, and pull request messages. Any other word that names the
# directory counts, even inside an interpreter's script.
aug_cfg_free_text() { # WORD
  case "$1" in *[[:space:]]*) ;; *) return 1 ;; esac
  case "$AW_CMD" in git|gh|glab) return 0 ;; esac
  return 1
}

# aug_glob_reaches PATTERN DIR ANCESTOR: pathname expansion of PATTERN can
# name DIR or something inside it (or, with ANCESTOR=1, a directory above it).
aug_glob_reaches() {
  local p="${1#/}" g="${2#/}" pc gc
  while [ -n "$g" ]; do
    [ -n "$p" ] || { [ "$3" = 1 ]; return; }
    pc="${p%%/*}"; gc="${g%%/*}"
    # shellcheck disable=SC2254
    case "$gc" in $pc) ;; *) return 1 ;; esac
    case "$p" in */*) p="${p#*/}" ;; *) p="" ;; esac
    case "$g" in */*) g="${g#*/}" ;; *) g="" ;; esac
  done
  return 0
}

# aug_cfg_word_hits WORD ANCESTOR: WORD names the policy directory, a path
# inside it, or (ANCESTOR=1) a directory that contains it.
aug_cfg_word_hits() {
  local w="$1" p
  case "$w" in
    *.config/augments-skills*|*augments-skills/policy.json*|*augments-skills/config.json*)
      aug_cfg_free_text "$w" || return 0 ;;
  esac
  aug_expand "$w" && w="$REPLY"
  case "$w" in *.config/augments-skills*) aug_cfg_free_text "$w" || return 0 ;; esac
  case "$w" in
    "") return 1 ;;
    --*=*) w="${w#*=}" ;;
    -*) return 1 ;;
  esac
  aug_abspath "$w" "${AW_CWD:-/nonexistent-cwd}"; p="$REPLY"
  aug_inside "$p" "$AUG_G" && return 0
  [ "$2" = 1 ] && aug_inside "$AUG_G" "$p" && return 0
  case "$p" in *[*?[]*) aug_glob_reaches "$p" "$AUG_G" "$2" && return 0 ;; esac
  return 1
}

aug_cfg_phys_hits() { # ABS
  [ -d "$AUG_G" ] || return 1
  if [ -z "$AUG_GP" ]; then aug_physpath "$AUG_G"; AUG_GP="$REPLY"; fi
  aug_physpath "$1"
  aug_inside "$REPLY" "$AUG_GP"
}

AUG_CFG_MSG="writes to ~/.config/augments-skills/ are reserved for the user (it holds the hook policy)"

aug_cfg_shell() {
  local k w last="" n a
  k=0
  while [ "$k" -lt "${#AW_ROP[@]}" ]; do
    case "${AW_ROP[$k]}" in
      '>'|'>>'|'>|'|'<>'|'&>'|'&>>'|'>&')
        w="${AW_RT[$k]}"
        case "$w" in -|[0-9]|[0-9][0-9]) ;; *)
          aug_cfg_word_hits "$w" 0 && { aug_deny "$AUG_CFG_MSG"; return; }
          aug_expand "$w" && w="$REPLY"
          aug_abspath "$w" "${AW_CWD:-/nonexistent-cwd}"
          aug_cfg_phys_hits "$REPLY" && { aug_deny "$AUG_CFG_MSG"; return; }
          ;;
        esac
        ;;
    esac
    k=$((k + 1))
  done
  [ "${#AW_WORDS[@]}" -gt 0 ] || return 0
  aug_cmd_readonly && return 0
  # A sh -c script is walked, and checked, as commands of its own.
  [ "$AW_HAS_SCRIPT" -eq 1 ] && return 0
  if [ -n "$AW_CWD" ] && aug_inside "$AW_CWD" "$AUG_G"; then aug_deny "$AUG_CFG_MSG"; return; fi
  n=${#AW_WORDS[@]}
  case "$AW_CMD" in cp|rsync|ln|install|scp) last="${AW_WORDS[$((n - 1))]}" ;; esac
  for w in "${AW_WORDS[@]:1}"; do
    case "$AW_CMD" in rm|rmdir|mv|unlink|trash) a=1 ;; *) a=0 ;; esac
    [ -n "$last" ] && [ "$w" = "$last" ] && a=1
    aug_cfg_word_hits "$w" "$a" && { aug_deny "$AUG_CFG_MSG"; return; }
  done
  return 0
}

aug_cfg_edit() { # PATH
  aug_abspath "$1" "${AUG_CWD:-/nonexistent-cwd}"
  local p="$REPLY"
  if aug_inside "$p" "$AUG_G" || aug_inside "$AUG_G" "$p" || aug_cfg_phys_hits "$p"; then
    aug_deny "$AUG_CFG_MSG"; return
  fi
  return 0
}

# ------------------------------------------------- guard-destructive-git --

aug_husky_check() {
  local a
  case "$AW_CMD" in
    ""|git|export|declare|typeset|readonly|local) ;;
    *) return 0 ;;
  esac
  for a in ${AW_ASSIGN[@]+"${AW_ASSIGN[@]}"} "${AW_WORDS[@]:1}"; do
    case "$a" in
      HUSKY=0|HUSKY_SKIP_HOOKS=?*) aug_deny "${a%%=*}=${a#*=} turns off the repository's git hooks"; return ;;
    esac
  done
  return 0
}

AUG_CACHE_DIRS=" node_modules dist build target .next .nuxt .turbo .cache __pycache__ .pytest_cache .mypy_cache .ruff_cache coverage .gradle out .parcel-cache .svelte-kit .tox "

# A recursive forced rm is allowed when the target is inside a temporary
# directory, or inside a build cache below the current directory.
aug_rm_target_ok() {
  local raw="$1" p fixed root c rest
  aug_expand "$raw" || return 1
  [ -n "$REPLY" ] || return 0
  aug_abspath "$REPLY" "${AW_CWD:-/nonexistent-cwd}"; p="$REPLY"
  rest=""
  [ -n "$AW_CWD" ] && [ "$p" != "$AW_CWD" ] && aug_inside "$p" "$AW_CWD" && rest="${p#"${AW_CWD%/}"/}"
  while [ -n "$rest" ]; do
    c="${rest%%/*}"
    case "$AUG_CACHE_DIRS" in *" $c "*) return 0 ;; esac
    case "$c" in *.egg-info) return 0 ;; esac
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
  done
  fixed="$p"
  case "$p" in *[*?[]*) fixed="${p%%[*?[]*}"; fixed="${fixed%/*}/x" ;; esac
  for root in "${TMPDIR:-}" /tmp /var/tmp; do
    [ -n "$root" ] || continue
    aug_native_path "$root"; aug_normpath "$REPLY"; root="$REPLY"
    [ "$root" = / ] && continue
    [ "$fixed" != "$root" ] && aug_inside "$fixed" "$root" && return 0
    if [ -d "$root" ]; then
      local pr pf
      aug_physpath "$root"; pr="$REPLY"
      aug_physpath "${fixed%/*}"; pf="$REPLY/${fixed##*/}"
      [ "$pf" != "$pr" ] && aug_inside "$pf" "$pr" && return 0
    fi
  done
  return 1
}

aug_rm_check() {
  local w rec=0 force=0 end=0
  local -a targets
  targets=()
  for w in "${AW_WORDS[@]:1}"; do
    if [ "$end" -eq 1 ]; then targets[${#targets[@]}]="$w"; continue; fi
    case "$w" in
      --) end=1 ;;
      --recursive) rec=1 ;;
      --force) force=1 ;;
      --*) ;;
      -?*)
        case "$w" in *[rR]*) rec=1 ;; esac
        case "$w" in *f*) force=1 ;; esac
        ;;
      *) targets[${#targets[@]}]="$w" ;;
    esac
  done
  [ "$rec" -eq 1 ] && [ "$force" -eq 1 ] || return 0
  if [ "$AW_OPAQUE" -eq 1 ]; then
    aug_deny "rm -rf on paths chosen at run time (xargs, find -exec) can delete anything"; return
  fi
  for w in ${targets[@]+"${targets[@]}"}; do
    aug_rm_target_ok "$w" || { aug_deny "rm -rf $w is outside the temporary directory and build caches"; return; }
  done
  return 0
}

aug_hookspath_check() {
  local w
  for w in ${G_CFG[@]+"${G_CFG[@]}"}; do
    case "$w" in
      [Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh]|[Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh]=*)
        aug_deny "git -c core.hooksPath on $G_SUB bypasses the repository's git hooks"; return ;;
    esac
  done
  return 0
}

# git config core.hooksPath VALUE turns the hooks off for every later command.
aug_config_hookspath_check() {
  local w set=0 key=0
  for w in ${G_ARGS[@]+"${G_ARGS[@]}"}; do
    case "$w" in
      --get|--get-all|--get-regexp|--list|-l|get|list|--show-origin|--unset|--unset-all|unset) return 0 ;;
      [Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh]) key=1 ;;
      -*) ;;
      *) [ "$key" -eq 1 ] && set=1 ;;
    esac
  done
  [ "$set" -eq 1 ] && { aug_deny "git config core.hooksPath turns off the repository's git hooks"; return; }
  return 0
}

aug_noverify_check() {
  local i=0 n=${#G_ARGS[@]} w j c
  while [ "$i" -lt "$n" ]; do
    w="${G_ARGS[$i]}"
    case "$w" in
      --) return 0 ;;
      --*)
        aug_lopt "$w" --no-verify 9 && { aug_deny "git $G_SUB --no-verify skips the repository's git hooks"; return; }
        case "$w" in
          --message|--file|--author|--date|--reuse-message|--reedit-message|--fixup|--squash|--template|--cleanup|--trailer|--pathspec-from-file|--strategy|--strategy-option) i=$((i + 1)) ;;
        esac
        ;;
      -[!-]*)
        if [ "$G_SUB" = commit ]; then
          j=1
          while [ "$j" -lt "${#w}" ]; do
            c="${w:$j:1}"
            case "$c" in
              n) aug_deny "git commit -n (--no-verify) skips the repository's git hooks"; return ;;
              [mFCct]) [ "$j" -eq $((${#w} - 1)) ] && i=$((i + 1)); break ;;
              [Su]) break ;;
            esac
            j=$((j + 1))
          done
        else
          case "$w" in -m|-F|-s|-X) i=$((i + 1)) ;; esac
        fi
        ;;
    esac
    i=$((i + 1))
  done
  return 0
}

aug_destructive_push() {
  local t
  aug_git_repo || R_BRANCH=""
  aug_push_parse
  [ "$P_DRY" -eq 1 ] && return 0
  [ "$P_NOVERIFY" -eq 1 ] && { aug_deny "git push --no-verify skips the pre-push hook"; return; }
  [ "$P_MIRROR" -eq 1 ] && { aug_deny "git push --mirror overwrites and deletes remote refs"; return; }
  if [ "$P_FORCE" -eq 1 ] || [ -n "$P_FORCED_REFS" ]; then
    aug_deny "a forced git push (--force, -f, +refspec) overwrites remote history; on your own feature branch use --force-with-lease"; return
  fi
  [ "$P_LEASE" -eq 1 ] || return 0
  [ "$POL_FWL" = block ] && { aug_deny "git push --force-with-lease is turned off by the user's policy"; return; }
  [ -n "$R_TOP" ] || [ -n "$R_MAIN" ] || return 0
  aug_protected_load
  aug_push_default_targets
  [ "$P_ALL" -eq 1 ] && { aug_deny "git push --force-with-lease --all can rewrite protected branches"; return; }
  for t in ${P_TGT[@]+"${P_TGT[@]}"}; do
    aug_is_protected "$t" && { aug_deny "git push --force-with-lease rewrites protected branch '$t'"; return; }
  done
  return 0
}

aug_clean_check() {
  local w force=0 dry=0
  for w in ${G_ARGS[@]+"${G_ARGS[@]}"}; do
    case "$w" in
      --) break ;;
      --*)
        aug_lopt "$w" --force 3 && force=1
        aug_lopt "$w" --dry-run 3 && dry=1
        ;;
      -[!-]*)
        aug_short "$w" f e && force=1
        aug_short "$w" n e && dry=1
        ;;
    esac
  done
  [ "$dry" -eq 1 ] && return 0
  if [ "$force" -eq 0 ]; then
    for w in ${G_CFG[@]+"${G_CFG[@]}"}; do
      case "$w" in [Cc][Ll][Ee][Aa][Nn].[Rr][Ee][Qq][Uu][Ii][Rr][Ee][Ff][Oo][Rr][Cc][Ee]=*) force=1 ;; esac
    done
    [ "$force" -eq 1 ] || [ "$(aug_gitq config --bool clean.requireForce)" != false ] || force=1
  fi
  [ "$force" -eq 1 ] && { aug_deny "git clean -f deletes untracked files for good (try git clean -n first)"; return; }
  return 0
}

aug_checkout_check() {
  local i=0 n=${#G_ARGS[@]} w after=0
  while [ "$i" -lt "$n" ]; do
    w="${G_ARGS[$i]}"
    if [ "$after" -eq 1 ]; then
      aug_whole_tree "$w" && { aug_deny "git $G_SUB -- $w discards every uncommitted change under it"; return; }
    else
      case "$w" in
        --) after=1 ;;
        -b|-B|-c|-C|--orphan|--conflict|--pathspec-from-file) i=$((i + 1)) ;;
        --*)
          if aug_lopt "$w" --force 5 || aug_lopt "$w" --discard-changes 5; then
            aug_deny "git $G_SUB $w discards uncommitted changes"; return
          fi
          ;;
        -[!-]*) aug_short "$w" f bBcC && { aug_deny "git $G_SUB -f discards uncommitted changes"; return; } ;;
        *)
          [ "$G_SUB" = checkout ] && aug_whole_tree "$w" &&
            { aug_deny "git checkout $w discards every uncommitted change under it"; return; }
          ;;
      esac
    fi
    i=$((i + 1))
  done
  return 0
}

aug_restore_check() {
  local i=0 n=${#G_ARGS[@]} w after=0 staged=0 worktree=0 whole=""
  while [ "$i" -lt "$n" ]; do
    w="${G_ARGS[$i]}"
    if [ "$after" -eq 1 ]; then
      aug_whole_tree "$w" && whole="$w"
    else
      case "$w" in
        --) after=1 ;;
        -s|--source|--pathspec-from-file) i=$((i + 1)) ;;
        --*)
          aug_lopt "$w" --staged 4 && staged=1
          aug_lopt "$w" --worktree 3 && worktree=1
          ;;
        -[!-]*)
          aug_short "$w" S s && staged=1
          aug_short "$w" W s && worktree=1
          case "$w" in *s) i=$((i + 1)) ;; esac
          ;;
        *) aug_whole_tree "$w" && whole="$w" ;;
      esac
    fi
    i=$((i + 1))
  done
  [ -n "$whole" ] || return 0
  [ "$staged" -eq 1 ] && [ "$worktree" -eq 0 ] && return 0
  aug_deny "git restore $whole discards every uncommitted change under it"
}

aug_branch_check() {
  local w del=0 force=0 remote=0 after=0 b tip up
  local -a names
  names=()
  for w in ${G_ARGS[@]+"${G_ARGS[@]}"}; do
    if [ "$after" -eq 1 ]; then names[${#names[@]}]="$w"; continue; fi
    case "$w" in
      --) after=1 ;;
      --*)
        aug_lopt "$w" --delete 4 && del=1
        aug_lopt "$w" --force 5 && force=1
        aug_lopt "$w" --remotes 5 && remote=1
        ;;
      -[!-]*)
        aug_short "$w" D "" && { del=1; force=1; }
        aug_short "$w" d "" && del=1
        aug_short "$w" f "" && force=1
        aug_short "$w" r "" && remote=1
        ;;
      *) names[${#names[@]}]="$w" ;;
    esac
  done
  [ "$del" -eq 1 ] && [ "$force" -eq 1 ] && [ "$remote" -eq 0 ] || return 0
  aug_git_repo || return 0
  for b in ${names[@]+"${names[@]}"}; do
    tip="$(aug_gitq rev-parse -q --verify "refs/heads/$b^{commit}")" || continue
    aug_gitq merge-base --is-ancestor "$tip" HEAD && continue
    up="$(aug_gitq rev-parse -q --verify "$b@{upstream}")" &&
      aug_gitq merge-base --is-ancestor "$tip" "$up" && continue
    aug_deny "git branch -D $b deletes commits that are in neither HEAD nor its upstream"; return
  done
  return 0
}

aug_destructive_shell() {
  aug_husky_check || return 1
  case "$AW_CMD" in
    rm) aug_rm_check; return ;;
    git) aug_git_parse || return 0 ;;
    *) return 0 ;;
  esac
  case "$G_SUB" in
    commit|push|merge|am|rebase|cherry-pick|revert|pull) aug_hookspath_check || return 1 ;;
  esac
  local w
  case "$G_SUB" in
    reset)
      for w in ${G_ARGS[@]+"${G_ARGS[@]}"}; do
        [ "$w" = -- ] && break
        aug_lopt "$w" --hard 4 && { aug_deny "git reset --hard discards uncommitted work"; return; }
      done
      return 0
      ;;
    push) aug_destructive_push ;;
    clean) aug_clean_check ;;
    checkout|switch) aug_checkout_check ;;
    restore) aug_restore_check ;;
    stash) if [ "${G_ARGS[0]-}" = clear ]; then aug_deny "git stash clear deletes every stash"; return; fi ;;
    branch) aug_branch_check ;;
    commit|merge) aug_noverify_check ;;
    config) aug_config_hookspath_check ;;
  esac
}

# ------------------------------------------------ guard-protected-branch --

aug_protected_push() {
  local t
  aug_push_parse
  [ "$P_DRY" -eq 1 ] && return 0
  aug_push_default_targets
  if [ "$P_ALL" -eq 1 ] || [ "$P_MIRROR" -eq 1 ]; then
    aug_repo_exempt && return 0
    aug_deny "git push --all or --mirror updates protected branches"; return
  fi
  for t in ${P_TGT[@]+"${P_TGT[@]}"}; do
    if aug_is_protected "$t"; then
      aug_repo_exempt && return 0
      aug_deny "git push to protected branch '$t'; push a feature branch and open a pull request"; return
    fi
  done
  return 0
}

# aug_track_switch: after git switch or a branch checkout earlier in the
# same command line (git switch -c topic && git commit), later commands in
# that work tree run on the new branch. Sets AUG_SW_TOP and AUG_SW_BRANCH
# ("" when detached). Needs aug_git_repo.
aug_track_switch() {
  local i=0 n=${#G_ARGS[@]} w new="" set=0 pos=""
  local -a p
  p=()
  while [ "$i" -lt "$n" ]; do
    w="${G_ARGS[$i]}"
    case "$w" in
      --) [ "$G_SUB" = checkout ] && return 0; break ;;
      -b|-B|-c|-C|--create|--force-create|--orphan) i=$((i + 1)); new="${G_ARGS[$i]-}"; set=1 ;;
      --create=*|--force-create=*|--orphan=*) new="${w#*=}"; set=1 ;;
      -[bBcC]?*) new="${w#-?}"; set=1 ;;
      --detach|-d) set=1 ;;
      --patch|-p|--pathspec-from-file*) return 0 ;;
      --conflict) i=$((i + 1)) ;;
      -*) ;;
      *) p[${#p[@]}]="$w" ;;
    esac
    i=$((i + 1))
  done
  if [ "$set" -eq 0 ]; then
    [ "${#p[@]}" -eq 1 ] || return 0
    pos="${p[0]}"
    if [ "$pos" = - ]; then
      new="$(aug_gitq rev-parse --abbrev-ref @{-1})" || return 0
    elif aug_gitq show-ref --verify -q "refs/heads/$pos"; then
      new="$pos"
    elif [ -n "$(aug_gitq for-each-ref --count=1 --format=x "refs/remotes/*/$pos")" ]; then
      new="$pos"
    elif [ "$G_SUB" = switch ] || aug_gitq rev-parse -q --verify "$pos^{commit}" >/dev/null; then
      new=""
    else
      return 0
    fi
  fi
  AUG_SW_TOP="$R_TOP" AUG_SW_BRANCH="$new"
}

aug_protected_shell() {
  [ "$AW_CMD" = git ] || return 0
  aug_git_parse || return 0
  case "$G_SUB" in
    switch|checkout) aug_git_repo && aug_track_switch; return 0 ;;
    commit|merge|cherry-pick|revert|am|push) ;;
    *) return 0 ;;
  esac
  aug_git_repo || return 0
  [ -n "$AUG_SW_TOP" ] && [ "$R_TOP" = "$AUG_SW_TOP" ] && R_BRANCH="$AUG_SW_BRANCH"
  aug_protected_load
  if [ "$G_SUB" = push ]; then aug_protected_push; return; fi
  aug_is_protected "$R_BRANCH" || return 0
  local w
  for w in ${G_ARGS[@]+"${G_ARGS[@]}"}; do
    case "$G_SUB:$w" in
      commit:--dry-run|merge:--ff-only|merge:--abort|merge:--quit|merge:--squash|merge:--no-commit) return 0 ;;
      cherry-pick:--abort|cherry-pick:--quit|cherry-pick:--skip|cherry-pick:--no-commit|cherry-pick:-n) return 0 ;;
      revert:--abort|revert:--quit|revert:--skip|revert:--no-commit|revert:-n) return 0 ;;
      am:--abort|am:--quit|am:--skip|am:--show-current-patch*) return 0 ;;
    esac
  done
  aug_repo_exempt && return 0
  aug_deny "git $G_SUB on protected branch '$R_BRANCH'; create a feature branch first (git switch -c <name>)"
}

aug_protected_edit() { # PATH
  local p d
  aug_abspath "$1" "${AUG_CWD:-/nonexistent-cwd}"; p="$REPLY"
  d="${p%/*}"
  while [ -n "$d" ] && [ ! -d "$d" ]; do d="${d%/*}"; done
  [ -n "$d" ] || d=/
  G_CWD="$d" G_GITDIR="" G_WT=""
  aug_git_repo || return 0
  [ -n "$R_TOP" ] || return 0
  aug_protected_load
  aug_is_protected "$R_BRANCH" || return 0
  aug_gitq check-ignore -q -- "$p" && return 0
  aug_repo_exempt && return 0
  aug_deny "editing $p on protected branch '$R_BRANCH'; create a feature branch first (git switch -c <name>)"
}

# ------------------------------------------------------------- dispatch --

aug_shell_cb() {
  aug_cfg_shell || return 1
  aug_hook_disabled "$AUG_HOOK" && return 0
  case "$AUG_HOOK" in
    guard-destructive-git) aug_destructive_shell ;;
    guard-protected-branch) aug_protected_shell ;;
  esac
}

# aug_run_checks HOOK KIND: KIND is shell (AUG_COMMAND) or edit (AUG_PATHS[]),
# both relative to AUG_CWD. Returns 1 with AUG_REASON set to deny.
aug_run_checks() {
  local p
  AUG_HOOK="$1" AUG_REASON="" AUG_GP="" AUG_SW_TOP="" AUG_SW_BRANCH=""
  aug_policy_load
  aug_guard_dir; AUG_G="$REPLY"
  case "$2" in
    shell) aug_walk "$AUG_COMMAND" "$AUG_CWD" 0 aug_shell_cb || return 1 ;;
    edit)
      for p in ${AUG_PATHS[@]+"${AUG_PATHS[@]}"}; do
        [ -n "$p" ] || continue
        aug_cfg_edit "$p" || return 1
        aug_hook_disabled "$AUG_HOOK" && continue
        if [ "$AUG_HOOK" = guard-protected-branch ]; then aug_protected_edit "$p" || return 1; fi
      done
      ;;
  esac
  return 0
}
