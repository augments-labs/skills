# Splits a shell command line into simple commands without running anything.
# POSIX awk, no extensions. Reads the script on stdin.
#
# Output records, one per line, fields separated by \037:
#   W <word>            a word with quotes removed
#   R <op> <target>     a redirection (<, >, >>, >|, <>, <&, >&, &>, &>>, <<, <<-, <<<)
#   H <n> <body>        here-document body for simple command number n (0-based)
#   E [|]               end of a simple command; "|" when it pipes into the next
# Newlines inside a word or body are written as \036. Command substitutions
# ($(...), `...`) and process substitutions (<(...), >(...)) are tokenized as
# separate command lists after the current one; their text stays in the word.

BEGIN { US = "\037"; NLM = "\036"; nq = 0; cmdno = 0 }
{ src = src $0 "\n" }
END {
  q[nq++] = src
  for (qi = 0; qi < nq; qi++) tok(q[qi])
}

function out(t, v) { gsub(/\n/, NLM, v); print t US v }

function flush() {
  if (!have) return
  if (rop != "") {
    out("R", rop US cur)
    if (rop == "<<" || rop == "<<-") { hd_n++; hd_del[hd_n] = cur; hd_strip[hd_n] = (rop == "<<-"); hd_cmd[hd_n] = cmdno }
    rop = ""
  } else out("W", cur)
  cur = ""; have = 0; quoted = 0
}

function endcmd() { flush(); rop = ""; print "E"; cmdno++ }
function endpipe() { flush(); rop = ""; print "E" US "|"; cmdno++ }

# Index of the ")" matching the "(" at position p, honoring quotes; n if none.
function match_paren(p,   depth, j, c, e) {
  depth = 0
  for (j = p; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\\") { j++; continue }
    if (c == "'") { e = index(substr(s, j + 1), "'"); if (e == 0) return n; j += e; continue }
    if (c == "\"") {
      for (j++; j <= n; j++) { c = substr(s, j, 1); if (c == "\\") { j++; continue } if (c == "\"") break }
      continue
    }
    if (c == "(") depth++
    else if (c == ")") { depth--; if (depth == 0) return j }
  }
  return n
}

# Index of the closing backtick for the one at position p; n if none.
function match_tick(p,   j, c) {
  for (j = p + 1; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\\") { j++; continue }
    if (c == "`") return j
  }
  return n
}

# Handles "$..." at position i; appends to cur and advances i.
function dollar(   d, j, e) {
  d = substr(s, i + 1, 1)
  if (d == "(") {
    j = match_paren(i + 1)
    if (substr(s, i + 2, 1) != "(") q[nq++] = substr(s, i + 2, j - i - 2)
    cur = cur substr(s, i, j - i + 1); i = j
  } else if (d == "{") {
    e = index(substr(s, i), "}")
    if (e == 0) e = n - i + 1
    cur = cur substr(s, i, e); i = i + e - 1
  } else cur = cur "$"
  have = 1
}

function tick(   j, inner) {
  j = match_tick(i)
  inner = substr(s, i + 1, j - i - 1)
  gsub(/\\`/, "`", inner)
  q[nq++] = inner
  cur = cur substr(s, i, j - i + 1); i = j; have = 1
}

function read_heredocs(   h, line, e, cmp, body) {
  for (h = 1; h <= hd_n; h++) {
    body = ""
    while (i < n) {
      e = index(substr(s, i + 1), "\n")
      if (e == 0) { line = substr(s, i + 1); i = n } else { line = substr(s, i + 1, e - 1); i = i + e }
      cmp = line
      if (hd_strip[h]) sub(/^\t+/, "", cmp)
      if (cmp == hd_del[h]) break
      body = body line "\n"
    }
    out("H", hd_cmd[h] US body)
  }
  hd_n = 0
}

function ansi_c(   j, c, d) {
  for (j = i + 2; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "'") break
    if (c == "\\") {
      j++; d = substr(s, j, 1)
      if (d == "n") cur = cur "\n"
      else if (d == "t") cur = cur "\t"
      else cur = cur d
      continue
    }
    cur = cur c
  }
  i = j; have = 1; quoted = 1
}

function dquote(   c, d) {
  for (i++; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\"") break
    if (c == "\\") {
      d = substr(s, i + 1, 1)
      if (d == "\n") { i++; continue }
      if (d == "$" || d == "`" || d == "\"" || d == "\\") { cur = cur d; i++; continue }
      cur = cur c; continue
    }
    if (c == "$") { dollar(); continue }
    if (c == "`") { tick(); continue }
    cur = cur c
  }
  have = 1; quoted = 1
}

function tok(text,   c, d, e, j) {
  s = text; n = length(s); cur = ""; have = 0; quoted = 0; rop = ""; hd_n = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "'") {
      e = index(substr(s, i + 1), "'")
      if (e == 0) { cur = cur substr(s, i + 1); i = n } else { cur = cur substr(s, i + 1, e - 1); i += e }
      have = 1; quoted = 1; continue
    }
    if (c == "\"") { dquote(); continue }
    if (c == "\\") {
      d = substr(s, i + 1, 1); i++
      if (d != "\n") { cur = cur d; have = 1; quoted = 1 }
      continue
    }
    if (c == "$") {
      if (substr(s, i + 1, 1) == "'") { ansi_c(); continue }
      dollar(); continue
    }
    if (c == "`") { tick(); continue }
    if (c == " " || c == "\t") { flush(); continue }
    if (c == "\n") { endcmd(); if (hd_n) read_heredocs(); continue }
    if (c == ";") { endcmd(); while (substr(s, i + 1, 1) == ";" || substr(s, i + 1, 1) == "&") i++; continue }
    if (c == "&") {
      d = substr(s, i + 1, 1)
      if (d == ">") {
        flush()
        if (substr(s, i + 2, 1) == ">") { rop = "&>>"; i += 2 } else { rop = "&>"; i++ }
        continue
      }
      if (d == "&") i++
      endcmd(); continue
    }
    if (c == "|") {
      d = substr(s, i + 1, 1)
      if (d == "|") { i++; endcmd() } else { if (d == "&") i++; endpipe() }
      continue
    }
    if ((c == "<" || c == ">") && substr(s, i + 1, 1) == "(") {
      j = match_paren(i + 1)
      q[nq++] = substr(s, i + 2, j - i - 2)
      cur = cur substr(s, i, j - i + 1); i = j; have = 1; continue
    }
    if (c == "<" || c == ">") {
      if (have && !quoted && cur ~ /^[0-9]+$/) { cur = ""; have = 0 } else flush()
      d = substr(s, i + 1, 1)
      if (c == "<") {
        if (d == "<") {
          if (substr(s, i + 2, 1) == "<") { rop = "<<<"; i += 2 }
          else if (substr(s, i + 2, 1) == "-") { rop = "<<-"; i += 2 }
          else { rop = "<<"; i++ }
        } else if (d == ">" || d == "&") { rop = c d; i++ }
        else rop = "<"
      } else {
        if (d == ">" || d == "|" || d == "&") { rop = c d; i++ } else rop = ">"
      }
      continue
    }
    if (c == "(" || c == ")") { endcmd(); continue }
    if (c == "#" && !have) {
      e = index(substr(s, i), "\n")
      if (e == 0) i = n; else i = i + e - 2
      continue
    }
    cur = cur c; have = 1
  }
  endcmd()
}
