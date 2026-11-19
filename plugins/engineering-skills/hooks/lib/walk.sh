# Walks a shell command line one simple command at a time, without running
# it. Sourced, never executed. Needs common.sh.
#
# aug_walk SCRIPT CWD DEPTH CALLBACK
#   Calls CALLBACK once per simple command with these globals set:
#     AW_WORDS[]  words after assignments and wrappers (sudo, env, xargs ...)
#     AW_CMD      basename of AW_WORDS[0] without .exe ("" for assignments)
#     AW_ASSIGN[] NAME=value assignments that apply to the command
#     AW_ROP[] AW_RT[]  redirection operators and targets
#     AW_CWD      directory the command runs in, "" when it cannot be known
#     AW_OPAQUE   1 when more arguments arrive at run time (xargs, find -exec)
#   Recurses into bash/sh -c scripts, eval, here-documents and here-strings
#   fed to a shell, and echo/printf piped into a shell. Tracks cd, pushd,
#   env -C, and plain variable assignments for later expansion.
#   Returns 1 as soon as CALLBACK returns 1.

AUG_MAX_DEPTH=6

# aug_var NAME: REPLY = value of a variable assigned earlier in the walked
# script, else of the hook's own environment. Returns 1 when unknown.
aug_var() {
  local i=${#AWV_N[@]}
  while [ "$i" -gt 0 ]; do
    i=$((i - 1))
    if [ "${AWV_N[$i]}" = "$1" ]; then REPLY="${AWV_V[$i]}"; return 0; fi
  done
  if [ "$1" = PWD ] && [ -n "$AW_CUR" ]; then REPLY="$AW_CUR"; return 0; fi
  REPLY="${!1-}"
  [ -n "$REPLY" ]
}

# aug_expand WORD: REPLY = WORD with ~, $NAME and ${NAME} expanded.
# Returns 1 (REPLY = WORD) when it holds anything that cannot be known
# statically: command substitution, unknown variables, ${x:-y} forms.
aug_expand() {
  local w="$1" out="" name rest
  case "$w" in
    "~") w="${HOME:-}" ;;
    "~/"*) w="${HOME:-}/${w#??}" ;;
  esac
  while :; do
    case "$w" in
      *'$'*) ;;
      *) out="$out$w"; break ;;
    esac
    out="$out${w%%\$*}"
    w="${w#*\$}"
    case "$w" in
      "{"*)
        name="${w#\{}"
        case "$name" in *"}"*) ;; *) REPLY="$1"; return 1 ;; esac
        rest="${name#*\}}"
        name="${name%%\}*}"
        ;;
      [A-Za-z_]*)
        name="${w%%[!A-Za-z0-9_]*}"
        rest="${w#"$name"}"
        ;;
      *) REPLY="$1"; return 1 ;;
    esac
    case "$name" in ""|[0-9]*|*[!A-Za-z0-9_]*) REPLY="$1"; return 1 ;; esac
    aug_var "$name" || { REPLY="$1"; return 1; }
    out="$out$REPLY"
    w="$rest"
  done
  case "$out" in *'`'*) REPLY="$1"; return 1 ;; esac
  REPLY="$out"
}

aug_is_assignment() {
  case "$1" in
    [A-Za-z_]*=*) case "${1%%=*}" in *[!A-Za-z0-9_+]*) return 1 ;; esac; return 0 ;;
  esac
  return 1
}

aug_record_var() { # NAME=value
  local v="${1#*=}"
  aug_expand "$v" || v=""
  AWV_N[${#AWV_N[@]}]="${1%%=*}"
  AWV_V[${#AWV_V[@]}]="$v"
}

# aug_chdir TARGET: moves AW_CUR the way cd would; "" when unknowable.
aug_chdir() {
  if [ -z "$1" ]; then AW_CUR="${HOME:-}"; return; fi
  if [ "$1" = "-" ] || ! aug_expand "$1"; then AW_CUR=""; return; fi
  local t="$REPLY"
  aug_native_path "$t"; t="$REPLY"
  case "$t" in
    /*) aug_normpath "$t"; AW_CUR="$REPLY" ;;
    *) if [ -n "$AW_CUR" ]; then aug_normpath "$AW_CUR/$t"; AW_CUR="$REPLY"; fi ;;
  esac
}

aug_is_shell() {
  case "$1" in bash|sh|zsh|dash|ksh|ash|mksh|busybox) return 0 ;; esac
  return 1
}

# Strips wrappers from AW_WORDS until a real command is first. Sets
# AW_SHELL_SCRIPT (for sh -c), AW_STDIN_SHELL, AW_EVAL, AW_SKIP.
aug_unwrap() {
  local w c i j n opt
  while [ "${#AW_WORDS[@]}" -gt 0 ]; do
    w="${AW_WORDS[0]}"
    c="${w##*/}"; c="${c%.exe}"
    n=${#AW_WORDS[@]}
    i=1
    case "$c" in
      '{'|'}'|'!'|if|then|else|elif|fi|do|done|while|until|time|'[['|']]')
        if [ "$c" = time ]; then
          while [ "$i" -lt "$n" ] && [ "${AW_WORDS[$i]}" = -p ]; do i=$((i + 1)); done
        fi
        ;;
      for|case|select|function|esac|in) AW_SKIP=1; return ;;
      sudo|doas)
        while [ "$i" -lt "$n" ]; do
          opt="${AW_WORDS[$i]}"
          case "$opt" in
            --) i=$((i + 1)); break ;;
            -u|-g|-h|-p|-C|-D|-R|-T|-U|-r|-t|--user|--group|--host|--prompt|--chdir|--role|--type|--other-user|--close-from)
              [ "$opt" = -D ] || [ "$opt" = --chdir ] && aug_chdir "${AW_WORDS[$((i + 1))]}"
              i=$((i + 2)) ;;
            --chdir=*) aug_chdir "${opt#*=}"; i=$((i + 1)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      env)
        while [ "$i" -lt "$n" ]; do
          opt="${AW_WORDS[$i]}"
          case "$opt" in
            --) i=$((i + 1)); break ;;
            -u|-P|--unset) i=$((i + 2)) ;;
            -C|--chdir) aug_chdir "${AW_WORDS[$((i + 1))]}"; i=$((i + 2)) ;;
            --chdir=*) aug_chdir "${opt#*=}"; i=$((i + 1)) ;;
            -S|--split-string)
              AW_SPLIT="${AW_WORDS[$((i + 1))]}"; i=$((i + 2))
              j=$i; while [ "$j" -lt "$n" ]; do AW_SPLIT="$AW_SPLIT ${AW_WORDS[$j]}"; j=$((j + 1)); done
              AW_WORDS=(); return ;;
            --split-string=*|-S?*)
              case "$opt" in -S?*) AW_SPLIT="${opt#-S}" ;; *) AW_SPLIT="${opt#*=}" ;; esac
              i=$((i + 1))
              j=$i; while [ "$j" -lt "$n" ]; do AW_SPLIT="$AW_SPLIT ${AW_WORDS[$j]}"; j=$((j + 1)); done
              AW_WORDS=(); return ;;
            -*) i=$((i + 1)) ;;
            *) aug_is_assignment "$opt" || break
               AW_ASSIGN[${#AW_ASSIGN[@]}]="$opt"; i=$((i + 1)) ;;
          esac
        done
        ;;
      command)
        while [ "$i" -lt "$n" ]; do
          case "${AW_WORDS[$i]}" in
            -v|-V) AW_SKIP=1; return ;;
            -p) i=$((i + 1)) ;;
            --) i=$((i + 1)); break ;;
            *) break ;;
          esac
        done
        ;;
      exec)
        while [ "$i" -lt "$n" ]; do
          case "${AW_WORDS[$i]}" in
            -a) i=$((i + 2)) ;;
            -c|-l|-cl|-lc) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      nohup|chronic|unbuffer|caffeinate) ;;
      nice)
        while [ "$i" -lt "$n" ]; do
          case "${AW_WORDS[$i]}" in
            -n|--adjustment) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      timeout)
        while [ "$i" -lt "$n" ]; do
          case "${AW_WORDS[$i]}" in
            -s|-k|--signal|--kill-after) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) i=$((i + 1)); break ;;
          esac
        done
        ;;
      stdbuf|ionice)
        while [ "$i" -lt "$n" ]; do
          case "${AW_WORDS[$i]}" in
            -i|-o|-e|-c|-n|-p) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      xargs)
        AW_OPAQUE=1
        while [ "$i" -lt "$n" ]; do
          case "${AW_WORDS[$i]}" in
            -I|-L|-n|-P|-s|-d|-E|-a|--max-args|--max-lines|--max-procs|--max-chars|--delimiter|--arg-file|--eof|--process-slot-var) i=$((i + 2)) ;;
            --) i=$((i + 1)); break ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      find)
        # Only the -exec/-execdir/-ok part runs a command.
        j=1; i=0
        while [ "$j" -lt "$n" ]; do
          case "${AW_WORDS[$j]}" in -exec|-execdir|-ok|-okdir) i=$((j + 1)); break ;; esac
          j=$((j + 1))
        done
        if [ "$i" -eq 0 ]; then return; fi
        AW_OPAQUE=1
        j=$i
        while [ "$j" -lt "$n" ]; do
          case "${AW_WORDS[$j]}" in ';'|'+') break ;; esac
          j=$((j + 1))
        done
        AW_WORDS=("${AW_WORDS[@]:$i:$((j - i))}")
        continue
        ;;
      eval)
        AW_EVAL="${AW_WORDS[*]:1}"
        AW_WORDS=()
        return
        ;;
      *)
        if aug_is_shell "$c"; then aug_shell_args; fi
        return
        ;;
    esac
    AW_WORDS=("${AW_WORDS[@]:$i}")
    while [ "${#AW_WORDS[@]}" -gt 0 ] && aug_is_assignment "${AW_WORDS[0]}"; do
      AW_ASSIGN[${#AW_ASSIGN[@]}]="${AW_WORDS[0]}"
      AW_WORDS=("${AW_WORDS[@]:1}")
    done
  done
}

# For bash/sh/zsh ...: finds the -c script, or marks a shell that reads its
# script from stdin.
aug_shell_args() {
  local i=1 n=${#AW_WORDS[@]} w want_c=0
  while [ "$i" -lt "$n" ]; do
    w="${AW_WORDS[$i]}"
    case "$w" in
      --) i=$((i + 1)); break ;;
      -o|+o|-O|+O|--rcfile|--init-file) i=$((i + 2)); continue ;;
      --*) ;;
      -*c*) want_c=1 ;;
      -*|+*) ;;
      *) break ;;
    esac
    i=$((i + 1))
  done
  if [ "$want_c" -eq 1 ]; then
    [ "$i" -lt "$n" ] && AW_SHELL_SCRIPT="${AW_WORDS[$i]}" && AW_HAS_SCRIPT=1
    return
  fi
  # A script file operand means the script is not on the command line.
  [ "$i" -lt "$n" ] && [ "${AW_WORDS[$i]}" != -s ] || AW_STDIN_SHELL=1
}

# One simple command from the tokenizer, in AW_WORDS / AW_ROP / AW_RT.
aug_walk_command() {
  local cb="$1" depth="$2" k
  AW_ASSIGN=() AW_OPAQUE=0 AW_SKIP=0 AW_SHELL_SCRIPT="" AW_HAS_SCRIPT=0 AW_STDIN_SHELL=0 AW_EVAL="" AW_SPLIT=""
  local start_cwd="$AW_CUR"

  while [ "${#AW_WORDS[@]}" -gt 0 ] && aug_is_assignment "${AW_WORDS[0]}"; do
    AW_ASSIGN[${#AW_ASSIGN[@]}]="${AW_WORDS[0]}"
    AW_WORDS=("${AW_WORDS[@]:1}")
  done
  if [ "${#AW_WORDS[@]}" -eq 0 ]; then
    [ "${#AW_ASSIGN[@]}" -eq 0 ] && [ "${#AW_ROP[@]}" -eq 0 ] && return 0
    for k in ${AW_ASSIGN[@]+"${AW_ASSIGN[@]}"}; do aug_record_var "$k"; done
  else
    aug_unwrap
    [ "$AW_SKIP" -eq 1 ] && return 0
  fi

  AW_CMD=""
  if [ "${#AW_WORDS[@]}" -gt 0 ]; then
    AW_CMD="${AW_WORDS[0]##*/}"
    AW_CMD="${AW_CMD%.exe}"
  fi
  case "$AW_CMD" in
    export|declare|typeset|readonly|local)
      for k in "${AW_WORDS[@]:1}"; do aug_is_assignment "$k" && aug_record_var "$k"; done ;;
  esac

  # The command runs where env -C / sudo -D put it; cd then moves the shell.
  AW_CWD="$AW_CUR"
  "$cb" || return 1

  case "$AW_CMD" in
    cd|pushd)
      local t="" i=1
      while [ "$i" -lt "${#AW_WORDS[@]}" ]; do
        case "${AW_WORDS[$i]}" in -L|-P|-e|-@|--) ;; *) t="${AW_WORDS[$i]}"; break ;; esac
        i=$((i + 1))
      done
      AW_CUR="$start_cwd"
      aug_chdir "$t"
      ;;
    popd) AW_CUR="" ;;
    *) AW_CUR="$start_cwd" ;;
  esac

  # Nested scripts run in the command's own directory.
  local saved="$AW_CUR"
  if [ "$AW_HAS_SCRIPT" -eq 1 ]; then
    aug_walk "$AW_SHELL_SCRIPT" "$AW_CWD" $((depth + 1)) "$cb" || return 1
  fi
  if [ -n "$AW_EVAL" ]; then
    aug_walk "$AW_EVAL" "$AW_CWD" $((depth + 1)) "$cb" || return 1
  fi
  if [ -n "$AW_SPLIT" ]; then
    aug_walk "$AW_SPLIT" "$AW_CWD" $((depth + 1)) "$cb" || return 1
  fi
  if [ "$AW_STDIN_SHELL" -eq 1 ]; then
    k=0
    while [ "$k" -lt "${#AW_ROP[@]}" ]; do
      if [ "${AW_ROP[$k]}" = "<<<" ]; then
        aug_walk "${AW_RT[$k]}" "$AW_CWD" $((depth + 1)) "$cb" || return 1
      fi
      k=$((k + 1))
    done
    if [ -n "$AW_PIPED" ]; then
      aug_walk "$AW_PIPED" "$AW_CWD" $((depth + 1)) "$cb" || return 1
    fi
  fi
  AW_CUR="$saved"
  return 0
}

aug_walk() {
  local script="$1" depth="$3" cb="$4" out line t v n=0 stdin_shells=" " piped="" next_piped=""
  [ "$depth" -le "$AUG_MAX_DEPTH" ] || return 0
  local AW_CUR="$2"
  local -a AW_WORDS AW_ROP AW_RT AWV_N AWV_V
  AW_WORDS=() AW_ROP=() AW_RT=()
  if [ "$depth" -eq 0 ]; then AWV_N=() AWV_V=(); else AWV_N=(${AWV_N_OUT[@]+"${AWV_N_OUT[@]}"}) AWV_V=(${AWV_V_OUT[@]+"${AWV_V_OUT[@]}"}); fi
  out="$(awk -f "$AUG_LIB/shell.awk" <<<"$script")" || return 0
  while IFS= read -r line; do
    t="${line%%"$AUG_US"*}"
    v="${line#*"$AUG_US"}"
    case "$t" in
      W) AW_WORDS[${#AW_WORDS[@]}]="${v//$AUG_RS/$AUG_NL}" ;;
      R)
        AW_ROP[${#AW_ROP[@]}]="${v%%"$AUG_US"*}"
        v="${v#*"$AUG_US"}"
        AW_RT[${#AW_RT[@]}]="${v//$AUG_RS/$AUG_NL}"
        ;;
      E)
        next_piped=""
        if [ "$v" = "|" ] && [ "${#AW_WORDS[@]}" -gt 1 ]; then
          case "${AW_WORDS[0]##*/}" in echo|printf) next_piped="${AW_WORDS[*]:1}" ;; esac
        fi
        AW_PIPED="$piped"
        AWV_N_OUT=(${AWV_N[@]+"${AWV_N[@]}"}) AWV_V_OUT=(${AWV_V[@]+"${AWV_V[@]}"})
        if [ "${#AW_WORDS[@]}" -gt 0 ] || [ "${#AW_ROP[@]}" -gt 0 ]; then
          aug_walk_command "$cb" "$depth" || return 1
          [ "$AW_STDIN_SHELL" -eq 1 ] && stdin_shells="$stdin_shells$n "
        fi
        piped="$next_piped"
        AW_WORDS=() AW_ROP=() AW_RT=()
        n=$((n + 1))
        ;;
      H)
        case "$stdin_shells" in
          *" ${v%%"$AUG_US"*} "*)
            v="${v#*"$AUG_US"}"
            AWV_N_OUT=(${AWV_N[@]+"${AWV_N[@]}"}) AWV_V_OUT=(${AWV_V[@]+"${AWV_V[@]}"})
            aug_walk "${v//$AUG_RS/$AUG_NL}" "$AW_CUR" $((depth + 1)) "$cb" || return 1
            ;;
        esac
        ;;
    esac
  done <<EOF
$out
EOF
  return 0
}
