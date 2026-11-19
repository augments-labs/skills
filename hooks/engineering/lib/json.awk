# Minimal JSON reader for hook input and config files. POSIX awk, no extensions.
#
# Reads one JSON document on stdin. ENVIRON["AUG_JMODE"] selects the output:
#   check    nothing; exit status only
#   get      value at path ENVIRON["AUG_JPATH"] (strings decoded; literals raw)
#   array    elements of the array at AUG_JPATH, each decoded and followed by \037
#   keys     decoded string values whose path starts with AUG_JPATH and whose
#            last key matches the regex ENVIRON["AUG_JKEY"], one per line
#   multi    for each leaf whose path is in the space-separated list AUG_JPATH,
#            or is an element of an array at such a path:
#            path \037 type (s or l) \037 value \036
#   patch    file paths named by patch headers (*** Add/Update/Delete File:,
#            *** Move to:) in string values under AUG_JPATH, one per line
# Paths join object keys with "." and array indexes as [n]: tool_input.command,
# toolCall.args.CommandLine, protectedBranches[0]. Exit 1 on malformed JSON.

BEGIN { buf = "" }
{ buf = buf $0 "\n" }
END {
  mode = ENVIRON["AUG_JMODE"]; want = ENVIRON["AUG_JPATH"]; keyre = ENVIRON["AUG_JKEY"]
  if (mode == "") mode = "check"
  lex()
  if (bad) exit 1
  k = 1
  if (!pval("")) exit 1
  if (k != nt + 1) exit 1
  exit 0
}

# Tokens: { } [ ] : , s (string, raw escapes kept), l (literal).
# Splitting on '"' keeps the lexer linear even for large string values.
function lex(   m, p, seg, j, c, s, nb, lit, inside, L) {
  m = split(buf, parts, "\"")
  nt = 0; inside = 0; s = ""
  for (p = 1; p <= m; p++) {
    seg = parts[p]
    if (inside) {
      s = s seg
      if (p == m) { bad = 1; return }
      nb = 0; j = length(s)
      while (j > 0 && substr(s, j, 1) == "\\") { nb++; j-- }
      if (nb % 2 == 1) { s = s "\""; continue }
      tok("s", s); inside = 0; s = ""
      continue
    }
    lit = ""; L = length(seg)
    for (j = 1; j <= L; j++) {
      c = substr(seg, j, 1)
      if (c == "{" || c == "}" || c == "[" || c == "]" || c == ":" || c == ",") {
        if (lit != "") { tok("l", lit); lit = "" }
        tok(c, "")
      } else if (c == " " || c == "\t" || c == "\n" || c == "\r") {
        if (lit != "") { tok("l", lit); lit = "" }
      } else lit = lit c
    }
    if (lit != "") tok("l", lit)
    if (p < m) inside = 1
  }
}

function tok(t, v) { nt++; tt[nt] = t; tv[nt] = v }

function pval(path,   t) {
  if (k > nt) return 0
  t = tt[k]
  if (t == "{") return pobj(path)
  if (t == "[") return parr(path)
  if (t == "s") { leaf(path, "s", tv[k]); k++; return 1 }
  if (t == "l") {
    if (tv[k] !~ /^(true|false|null|-?[0-9][0-9.eE+-]*)$/) return 0
    leaf(path, "l", tv[k]); k++; return 1
  }
  return 0
}

function pobj(path,   key, sub_path) {
  k++
  if (tt[k] == "}") { k++; return 1 }
  while (1) {
    if (tt[k] != "s") return 0
    key = jdecode(tv[k]); k++
    if (tt[k] != ":") return 0
    k++
    if (path == "") sub_path = key; else sub_path = path "." key
    if (!pval(sub_path)) return 0
    if (tt[k] == ",") { k++; continue }
    if (tt[k] == "}") { k++; return 1 }
    return 0
  }
}

function parr(path,   idx) {
  k++; idx = 0
  if (tt[k] == "]") { k++; return 1 }
  while (1) {
    if (!pval(path "[" idx "]")) return 0
    idx++
    if (tt[k] == ",") { k++; continue }
    if (tt[k] == "]") { k++; return 1 }
    return 0
  }
}

function leaf(path, t, v,   last, n, lines, i, line, pfx, d, base) {
  if (mode == "multi") {
    base = path; sub(/\[[0-9]+\]$/, "", base)
    if (index(" " want " ", " " path " ") || (base != path && index(" " want " ", " " base " "))) {
      if (t == "s") printf "%s\037s\037%s\036", path, jdecode(v); else printf "%s\037l\037%s\036", path, v
    }
  } else if (mode == "get") {
    if (path == want) { if (t == "s") printf "%s", jdecode(v); else printf "%s", v }
  } else if (mode == "array") {
    pfx = want "["
    if (substr(path, 1, length(pfx)) == pfx && substr(path, length(pfx)) ~ /^\[[0-9]+\]$/) {
      if (t == "s") printf "%s\037", jdecode(v); else printf "%s\037", v
    }
  } else if (mode == "keys") {
    if (t != "s" || substr(path, 1, length(want)) != want) return
    last = path
    while ((d = index(last, ".")) > 0) last = substr(last, d + 1)
    while (sub(/\[[0-9]+\]$/, "", last)) ;
    if (last ~ keyre) print jdecode(v)
  } else if (mode == "patch") {
    if (t != "s" || substr(path, 1, length(want)) != want) return
    if (index(v, "*** ") == 0) return
    n = split(v, lines, "\\\\n")
    for (i = 1; i <= n; i++) {
      line = lines[i]
      if (line ~ /^\*\*\* (Add|Update|Delete) File: /) { sub(/^\*\*\* [A-Za-z]+ File: /, "", line); print jdecode(line) }
      else if (line ~ /^\*\*\* Move to: /) { sub(/^\*\*\* Move to: /, "", line); print jdecode(line) }
    }
  }
}

# Decodes JSON string escapes. \uXXXX becomes UTF-8 (surrogate pairs joined).
function jdecode(s,   a, m, p, out, seg, c, rest, h, cp, lo) {
  if (index(s, "\\") == 0) return s
  m = split(s, a, "\\")
  out = a[1]; p = 2
  while (p <= m) {
    seg = a[p]
    if (seg == "") { out = out "\\"; p++; if (p <= m) out = out a[p]; p++; continue }
    c = substr(seg, 1, 1); rest = substr(seg, 2)
    if (c == "n") out = out "\n" rest
    else if (c == "t") out = out "\t" rest
    else if (c == "r") out = out "\r" rest
    else if (c == "b") out = out "\b" rest
    else if (c == "f") out = out "\f" rest
    else if (c == "u") {
      cp = hexval(substr(rest, 1, 4)); rest = substr(rest, 5)
      if (cp >= 55296 && cp <= 56319 && rest == "" && p < m && substr(a[p + 1], 1, 1) == "u") {
        lo = hexval(substr(a[p + 1], 2, 4))
        if (lo >= 56320 && lo <= 57343) {
          cp = 65536 + (cp - 55296) * 1024 + (lo - 56320)
          p++; rest = substr(a[p], 6)
        }
      }
      out = out utf8(cp) rest
    } else out = out c rest
    p++
  }
  return out
}

function hexval(h,   i, d, v) {
  v = 0
  for (i = 1; i <= length(h); i++) {
    d = index("0123456789abcdef", tolower(substr(h, i, 1)))
    if (d == 0) return 63
    v = v * 16 + d - 1
  }
  return v
}

function utf8(cp) {
  if (cp < 128) return sprintf("%c", cp)
  if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
  if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
  return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}
