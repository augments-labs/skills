"""Shared by the verifiers. A verifier loads this file by path (they run with
`python3 -I`, so a plain import would not find it).

frontmatter(path) parses a SKILL.md header the way a strict YAML loader does
for the shapes skills use: top-level `key: value` pairs whose value is a
double- or single-quoted scalar, a plain scalar (possibly continued on
indented lines), a `|` or `>` block scalar, or a nested mapping. It returns
(fields, body, error); error is a string when a strict loader would reject
the header or drop the skill.
"""
import os
import re

KEY = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(?:\s(.*))?$")
INDICATORS = set("-?:,[]{}#&*!|>'\"%@`")
NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def _plain_ok(text):
    if not text:
        return True
    if text[0] in INDICATORS and not (text[0] in "-?:" and len(text) > 1 and not text[1].isspace()):
        return False
    return ": " not in text and " #" not in text and not text.endswith(":")


def _quoted(first, rest_lines, quote):
    text = first
    lines = list(rest_lines)
    consumed = 0
    while True:
        if quote == '"':
            s = re.sub(r'\\.', "", text[1:])
            if '"' in s:
                tail = s[s.index('"') + 1:].strip()
                return (None if tail and not tail.startswith("#") else text), consumed
        else:
            s = text[1:].replace("''", "")
            if "'" in s:
                tail = s[s.index("'") + 1:].strip()
                return (None if tail and not tail.startswith("#") else text), consumed
        if consumed >= len(lines):
            return None, consumed
        text += " " + lines[consumed].strip()
        consumed += 1


def _unquote(text, quote):
    inner = text.strip()[1:]
    if quote == '"':
        end = 0
        out = []
        while end < len(inner):
            c = inner[end]
            if c == "\\" and end + 1 < len(inner):
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(inner[end + 1], inner[end + 1]))
                end += 2
                continue
            if c == '"':
                break
            out.append(c)
            end += 1
        return "".join(out)
    return inner[: inner.index("'") if "''" not in inner else len(inner)].replace("''", "'").rstrip("'")


def frontmatter(path):
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as e:
        return {}, "", f"unreadable: {e}"
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text, "no frontmatter"
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return {}, text, "frontmatter not closed"
    head, body = lines[1:end], "\n".join(lines[end + 1:])
    fields, i = {}, 0
    while i < len(head):
        line = head[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if line[0].isspace():
            return {}, body, f"unexpected indented line: {line.strip()[:40]}"
        m = KEY.match(line.rstrip())
        if not m:
            return {}, body, f"not a key: {line[:40]}"
        key, value = m.group(1), (m.group(2) or "").strip()
        if key in fields:
            return {}, body, f"duplicate key {key}"
        cont = []
        j = i + 1
        while j < len(head) and (not head[j].strip() or head[j][0].isspace()):
            cont.append(head[j])
            j += 1
        while cont and not cont[-1].strip():
            cont.pop()
            j -= 1
        if value[:1] in ('"', "'"):
            q = value[0]
            got, used = _quoted(value, cont, q)
            if got is None:
                return {}, body, f"{key}: bad quoted scalar"
            if any(c.strip() for c in cont[used:]):
                return {}, body, f"{key}: text after quoted scalar"
            fields[key] = _unquote(got, q)
        elif value[:1] in ("|", ">"):
            parts = [c.strip() for c in cont]
            fields[key] = ("\n" if value[0] == "|" else " ").join(p for p in parts if p) if parts else ""
        elif value == "":
            if cont and any(KEY.match(c.strip()) or c.strip().startswith("- ") for c in cont if c.strip()):
                fields[key] = {}
            else:
                fields[key] = ""
        else:
            if value.startswith("#"):
                fields[key] = ""
            else:
                if not _plain_ok(value):
                    return {}, body, f"{key}: invalid plain scalar"
                parts = [value]
                for c in cont:
                    s = c.strip()
                    if s and not _plain_ok(s):
                        return {}, body, f"{key}: invalid plain scalar continuation"
                    if s:
                        parts.append(s)
                fields[key] = " ".join(parts)
        i = j
    return fields, body, None


def check_skill(skill_dir):
    """Problems a strict Agent Skills loader would reject, as a list of strings."""
    path = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(path):
        return ["no SKILL.md"]
    fields, _, err = frontmatter(path)
    if err:
        return [f"frontmatter: {err}"]
    out = []
    name = fields.get("name")
    if not isinstance(name, str) or not NAME.match(name) or len(name) > 64:
        out.append(f"name {name!r} is not kebab-case")
    elif name != os.path.basename(os.path.normpath(skill_dir)):
        out.append(f"name {name!r} does not match directory")
    desc = fields.get("description")
    if not isinstance(desc, str) or not desc.strip():
        out.append("description missing")
    elif len(desc) > 1024:
        out.append(f"description is {len(desc)} characters")
    return out


def skill_dirs(root):
    base = os.path.join(root, ".agents", "skills")
    if not os.path.isdir(base):
        return []
    return sorted(os.path.join(base, d) for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))


def load(name):
    import importlib.util
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
