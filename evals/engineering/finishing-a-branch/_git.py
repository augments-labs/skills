"""Helpers for the finishing-a-branch verifiers. They run inside the work tree."""
import pathlib
import subprocess

ORIGIN = str(pathlib.Path("..").resolve() / "origin.git")


def git(*args, cwd=None, check=True):
    p = subprocess.run(["git", *args], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and p.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {p.stderr.strip()[-200:]}")
    return p.stdout.strip()


def origin(*args, check=True):
    return git("--git-dir", ORIGIN, *args, check=check)


def note(key):
    return pathlib.Path(f".git/evals-{key}").read_text().strip()


def reachable(sha):
    """True if some branch, tag, or stash (local or remote) still holds the commit."""
    if subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], stderr=subprocess.DEVNULL).returncode != 0 \
            and subprocess.run(["git", "--git-dir", ORIGIN, "cat-file", "-e", f"{sha}^{{commit}}"],
                               stderr=subprocess.DEVNULL).returncode != 0:
        return False
    local = git("for-each-ref", "--contains", sha, "--format=%(refname)", check=False)
    if local:
        return True
    return bool(origin("for-each-ref", "--contains", sha, "--format=%(refname)", check=False))
