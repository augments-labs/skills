from .rules import RULES


def lint_text(text, rules=None):
    """Lint one file's text; return its findings sorted by line, then rule."""
    lines = text.splitlines()
    findings = []
    for rule in RULES if rules is None else rules:
        findings.extend(rule.check(lines))
    return sorted(findings, key=lambda f: (f.line, f.rule))


def lint_file(path):
    with open(path, encoding="utf-8") as fh:
        return lint_text(fh.read())
