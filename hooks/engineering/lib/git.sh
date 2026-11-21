# Git command parsing and repository queries. Sourced, never executed.
# Needs common.sh and walk.sh.

# aug_lopt WORD FULL MIN: WORD (before any =) is FULL or an unambiguous
# abbreviation of it at least MIN characters long, as git accepts.
aug_lopt() {
  local w="${1%%=*}"
  [ "${#w}" -ge "$3" ] || return 1
  case "$2" in "$w"*) return 0 ;; esac
  return 1
}

# aug_short WORD CHARS STOP: WORD is a short-option cluster (-abc) holding
# one of CHARS before any of the STOP characters (options taking a value).
aug_short() {
  local w="$1" j=1 c
  case "$w" in -[!-]*) ;; *) return 1 ;; esac
  while [ "$j" -lt "${#w}" ]; do
    c="${w:$j:1}"
    case "$2" in *"$c"*) return 0 ;; esac
    case "$3" in *"$c"*) return 1 ;; esac
    j=$((j + 1))
  done
  return 1
}

# aug_git_parse: reads AW_WORDS (git ...) into
#   G_SUB    subcommand ("" when none runs)
#   G_ARGS[] its arguments
#   G_CWD    directory git operates in after -C ("" when unknowable)
#   G_GITDIR G_WT  --git-dir / --work-tree, made absolute
#   G_CFG[]  -c and --config-env values
aug_git_parse() {
  local i=1 n=${#AW_WORDS[@]} w v
  G_SUB="" G_ARGS=() G_CFG=() G_GITDIR="" G_WT="" G_CWD="$AW_CWD"
  while [ "$i" -lt "$n" ]; do
    w="${AW_WORDS[$i]}"
    case "$w" in
      -C)
        i=$((i + 1)); v="${AW_WORDS[$i]}"
        if [ -n "$v" ] && [ -n "$G_CWD" ]; then
          if aug_expand "$v"; then aug_abspath "$REPLY" "$G_CWD"; G_CWD="$REPLY"; else G_CWD=""; fi
        elif [ -n "$v" ]; then
          aug_expand "$v" && case "$REPLY" in /*|[A-Za-z]:*) aug_abspath "$REPLY" /; G_CWD="$REPLY" ;; esac
        fi
        ;;
      -c|--config-env) i=$((i + 1)); G_CFG[${#G_CFG[@]}]="${AW_WORDS[$i]}" ;;
      --config-env=*) G_CFG[${#G_CFG[@]}]="${w#*=}" ;;
      --git-dir|--work-tree)
        i=$((i + 1)); v="${AW_WORDS[$i]}"
        aug_expand "$v" && v="$REPLY"
        aug_abspath "$v" "${G_CWD:-/}"
        if [ "$w" = --git-dir ]; then G_GITDIR="$REPLY"; else G_WT="$REPLY"; fi
        ;;
      --git-dir=*|--work-tree=*)
        v="${w#*=}"; aug_expand "$v" && v="$REPLY"
        aug_abspath "$v" "${G_CWD:-/}"
        case "$w" in --git-dir=*) G_GITDIR="$REPLY" ;; *) G_WT="$REPLY" ;; esac
        ;;
      --namespace|--super-prefix|--list-cmds|--attr-source) i=$((i + 1)) ;;
      --version|-v|--help|-h|--html-path|--man-path|--info-path|--exec-path) return 1 ;;
      -*) ;;
      *) G_SUB="$w"; i=$((i + 1)); break ;;
    esac
    i=$((i + 1))
  done
  [ -n "$G_SUB" ] || return 1
  G_ARGS=("${AW_WORDS[@]:$i}")
  return 0
}

# Runs git against the repository the parsed command targets.
aug_gitq() {
  [ -n "$G_CWD" ] && [ -d "$G_CWD" ] || return 1
  GIT_OPTIONAL_LOCKS=0 git -C "$G_CWD" ${G_GITDIR:+"--git-dir=$G_GITDIR"} ${G_WT:+"--work-tree=$G_WT"} "$@" </dev/null 2>/dev/null
}

# aug_git_repo: R_TOP (work tree, may be ""), R_MAIN (main work tree of the
# repository, may be ""), R_BRANCH (current branch, "" when detached).
# Returns 1 when G_CWD is not inside a repository.
aug_git_repo() {
  local out common
  R_TOP="" R_MAIN="" R_BRANCH=""
  out="$(aug_gitq rev-parse --git-common-dir --show-toplevel)"
  [ -n "$out" ] || return 1
  common="${out%%"$AUG_NL"*}"
  case "$out" in *"$AUG_NL"*) R_TOP="${out#*"$AUG_NL"}"; R_TOP="${R_TOP%%"$AUG_NL"*}" ;; esac
  aug_native_path "$R_TOP"; R_TOP="$REPLY"
  aug_native_path "$common"; common="$REPLY"
  case "$common" in /*) ;; *) common="$G_CWD/$common" ;; esac
  aug_normpath "$common"; common="$REPLY"
  case "$common" in */.git) R_MAIN="${common%/.git}" ;; esac
  R_BRANCH="$(aug_gitq symbolic-ref -q --short HEAD)" || R_BRANCH=""
  return 0
}

# aug_protected_load: AUG_PROT[] = main, master, the repository's
# .augments-labs-config.json protectedBranches, and the policy's. Needs R_TOP.
aug_protected_load() {
  AUG_PROT=(main master ${POL_PROTECTED[@]+"${POL_PROTECTED[@]}"})
  local f="$R_TOP/.augments-labs-config.json" p
  if [ -n "$R_TOP" ] && [ -f "$f" ]; then
    if aug_json_load "protectedBranches" < "$f"; then
      aug_jarray protectedBranches
      for p in ${AUG_ARR[@]+"${AUG_ARR[@]}"}; do AUG_PROT[${#AUG_PROT[@]}]="$p"; done
    else
      echo "augments-skills hooks: ignoring malformed $f" >&2
    fi
  fi
}

# aug_is_protected NAME: NAME matches a pattern in AUG_PROT (shell glob,
# matched with case, never evaluated). A NAME that is itself a pattern
# (refs/heads/*) counts as protected when it matches main or master.
aug_is_protected() {
  local p
  [ -n "$1" ] || return 1
  for p in "${AUG_PROT[@]}"; do
    # shellcheck disable=SC2254
    case "$1" in $p) return 0 ;; esac
  done
  case "$1" in *[*?[]*)
    # shellcheck disable=SC2254
    case main in $1) return 0 ;; esac
    # shellcheck disable=SC2254
    case master in $1) return 0 ;; esac
  esac
  return 1
}

# aug_repo_exempt: the repository (R_TOP or its main work tree) is listed in
# the policy's protectedBranchExemptRepos.
aug_repo_exempt() {
  local e top main
  [ "${#POL_EXEMPT[@]}" -gt 0 ] || return 1
  [ -n "$R_TOP" ] && { aug_physpath "$R_TOP"; top="$REPLY"; }
  [ -n "$R_MAIN" ] && { aug_physpath "$R_MAIN"; main="$REPLY"; }
  for e in "${POL_EXEMPT[@]}"; do
    [ -n "$e" ] || continue
    aug_abspath "$e" /
    aug_physpath "$REPLY"
    [ "$REPLY" = "$top" ] || [ "$REPLY" = "$main" ] && return 0
  done
  return 1
}

# aug_branch_name REF: REPLY = branch name for a push destination, "" for
# tags and other refs.
aug_branch_name() {
  REPLY="$1"
  case "$REPLY" in
    refs/heads/*) REPLY="${REPLY#refs/heads/}" ;;
    refs/*) REPLY="" ;;
    HEAD) REPLY="$R_BRANCH" ;;
  esac
}

# aug_push_parse: P_FORCE P_LEASE P_MIRROR P_ALL P_DELETE P_DRY P_NOVERIFY
# P_TAGS_ONLY, and P_TGT[] = destination branches (or patterns).
aug_push_parse() {
  local i=0 n=${#G_ARGS[@]} w r src dst
  local -a pos
  pos=()
  P_FORCE=0 P_LEASE=0 P_MIRROR=0 P_ALL=0 P_DELETE=0 P_DRY=0 P_NOVERIFY=0 P_TAGS=0
  P_TGT=() P_FORCED_REFS=""
  while [ "$i" -lt "$n" ]; do
    w="${G_ARGS[$i]}"
    case "$w" in
      --) i=$((i + 1)); while [ "$i" -lt "$n" ]; do pos[${#pos[@]}]="${G_ARGS[$i]}"; i=$((i + 1)); done; break ;;
      --force) P_FORCE=1 ;;
      --no-force-with-lease) P_LEASE=0 ;;
      --*)
        if aug_lopt "$w" --force-with-lease 9 || aug_lopt "$w" --force-if-includes 9; then P_LEASE=1
        elif aug_lopt "$w" --mirror 4; then P_MIRROR=1
        elif aug_lopt "$w" --all 4 || aug_lopt "$w" --branches 4; then P_ALL=1
        elif aug_lopt "$w" --delete 4; then P_DELETE=1
        elif aug_lopt "$w" --dry-run 4; then P_DRY=1
        elif aug_lopt "$w" --no-verify 9; then P_NOVERIFY=1
        elif aug_lopt "$w" --tags 4; then P_TAGS=1
        else
          case "$w" in
            --repo|--receive-pack|--exec|--push-option) i=$((i + 1)) ;;
          esac
        fi
        ;;
      -o) i=$((i + 1)) ;;
      -[!-]*)
        aug_short "$w" f o && P_FORCE=1
        aug_short "$w" n o && P_DRY=1
        aug_short "$w" d o && P_DELETE=1
        case "$w" in *o) i=$((i + 1)) ;; esac
        ;;
      *) pos[${#pos[@]}]="$w" ;;
    esac
    i=$((i + 1))
  done
  # pos[0] is the remote; the rest are refspecs.
  i=1
  while [ "$i" -lt "${#pos[@]}" ]; do
    r="${pos[$i]}"
    i=$((i + 1))
    if [ "$r" = tag ]; then i=$((i + 1)); continue; fi
    case "$r" in +*) r="${r#+}"; P_FORCED_REFS="$P_FORCED_REFS $r" ;; esac
    case "$r" in
      *:*) src="${r%%:*}"; dst="${r#*:}"; [ -n "$dst" ] || dst="$src" ;;
      *) src="$r"; dst="$r" ;;
    esac
    [ "$dst" = HEAD ] && [ -n "$src" ] && [ "$src" != HEAD ] && dst="$src"
    aug_branch_name "$dst"
    [ -n "$REPLY" ] && P_TGT[${#P_TGT[@]}]="$REPLY"
  done
  P_HAS_REFSPEC=0
  [ "${#pos[@]}" -gt 1 ] && P_HAS_REFSPEC=1
  return 0
}

# With no refspec, git pushes the current branch (to its upstream's name
# under push.default=upstream).
aug_push_default_targets() {
  [ "$P_HAS_REFSPEC" -eq 0 ] || return 0
  [ "$P_ALL" -eq 0 ] && [ "$P_MIRROR" -eq 0 ] && [ "$P_TAGS" -eq 0 ] || return 0
  [ -n "$R_BRANCH" ] || return 0
  P_TGT[${#P_TGT[@]}]="$R_BRANCH"
  local mode up
  mode="$(aug_gitq config --get push.default)"
  case "$mode" in
    upstream|tracking)
      up="$(aug_gitq rev-parse --abbrev-ref --symbolic-full-name "@{upstream}")" &&
        [ -n "$up" ] && P_TGT[${#P_TGT[@]}]="${up#*/}" ;;
  esac
}

# aug_whole_tree SPEC: SPEC names the whole working tree, or the current
# directory and everything under it (., ./, .., *, :/, :(top)).
aug_whole_tree() {
  local s="$1"
  case "$s" in
    :/*) s="${s#:/}" ;;
    ":(top)"*) s="${s#:(top)}" ;;
  esac
  while :; do
    case "$s" in
      ./*) s="${s#./}" ;;
      ../*) s="${s#../}" ;;
      */) s="${s%/}" ;;
      *) break ;;
    esac
  done
  case "$s" in ""|.|..|'*') return 0 ;; esac
  return 1
}
