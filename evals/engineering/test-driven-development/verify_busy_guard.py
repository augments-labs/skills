"""Exit 0 when every Syncer method that changes state raises SyncerBusy during
run() and leaves the syncer unchanged, reads still work, the guard lifts after a
failed run, and the work tree's own tests catch each guard being dropped."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "_mutation", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mutation.py"))
mutation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mutation)

HIDDEN = r'''
import sys
sys.path.insert(0, sys.argv[1])
from syncer.engine import Syncer
from syncer.errors import SyncerBusy
from syncer.sources import Source, StaticSource
from syncer.store import MemoryStore

problems = []

def fresh():
    s = Syncer(MemoryStore())
    s.add_source(StaticSource("a", [1]))
    s.add_source(StaticSource("b", [2]))
    return s

CALLS = {
    "add_source": lambda s: s.add_source(StaticSource("c", [3])),
    "remove_source": lambda s: s.remove_source("b"),
    "rename_source": lambda s: s.rename_source("b", "beta"),
    "set_interval": lambda s: s.set_interval(120),
    "clear": lambda s: s.clear(),
    "run": lambda s: s.run(),
}

for name, call in CALLS.items():
    s = fresh()
    seen = {}
    def progress(src, done, total, s=s, call=call, seen=seen):
        if done != 1:
            return
        before = (s.list_sources(), s.status()["interval"])
        try:
            call(s)
            seen["got"] = "no error"
        except SyncerBusy:
            seen["got"] = "SyncerBusy"
        except Exception as exc:
            seen["got"] = type(exc).__name__
        seen["unchanged"] = (s.list_sources(), s.status()["interval"]) == before
    try:
        s.run(progress=progress)
    except Exception as exc:
        seen.setdefault("got", "run raised " + type(exc).__name__)
    if seen.get("got") != "SyncerBusy":
        problems.append(f"{name}() during run(): {seen.get('got')}, want SyncerBusy")
    elif not seen.get("unchanged"):
        problems.append(f"{name}() during run() changed the syncer")
    try:
        call(s)
    except Exception as exc:
        problems.append(f"{name}() after run() finished: {type(exc).__name__}: {exc}")

s = fresh()
reads = {}
def read_progress(src, done, total):
    try:
        reads[src] = (s.list_sources(), s.status()["sources"])
    except Exception as exc:
        reads[src] = type(exc).__name__
s.run(progress=read_progress)
if reads.get("a") != (["a", "b"], 2):
    problems.append(f"reads during run(): {reads.get('a')!r}, want (['a', 'b'], 2)")

class Broken(Source):
    def fetch(self):
        raise RuntimeError("upstream down")

s = fresh()
s.add_source(Broken("bad"))
try:
    s.run()
    problems.append("run() with a failing source did not raise")
except RuntimeError:
    pass
except Exception as exc:
    problems.append(f"run() with a failing source raised {type(exc).__name__}, want the source's error")
try:
    s.remove_source("bad")
    s.run()
except Exception as exc:
    problems.append(f"the syncer stays busy after a failed run: {type(exc).__name__}: {exc}")
for p in problems:
    print("FAIL:", p)
sys.exit(1 if problems else 0)
'''

TEMPLATE = '''
import time
import syncer.engine as _m
from syncer.errors import DuplicateSource, SyncerBusy, UnknownSource

class Syncer:
    def __init__(self, store, interval=60):
        self.store = store
        self._sources = {}
        self._interval = interval
        self._last_run = None
        self._running = False

    def _idle(self):
        if self._running:
            raise SyncerBusy("the syncer is running")

    def add_source(self, source):
        __add_source__
        if source.name in self._sources:
            raise DuplicateSource(source.name)
        self._sources[source.name] = source

    def remove_source(self, name):
        __remove_source__
        if name not in self._sources:
            raise UnknownSource(name)
        del self._sources[name]

    def rename_source(self, old, new):
        __rename_source__
        if old not in self._sources:
            raise UnknownSource(old)
        if new in self._sources:
            raise DuplicateSource(new)
        source = self._sources.pop(old)
        source.name = new
        self._sources[new] = source

    def set_interval(self, seconds):
        __set_interval__
        if seconds < 10:
            raise ValueError("interval must be at least 10 seconds")
        self._interval = seconds

    def clear(self):
        __clear__
        self._sources.clear()

    def list_sources(self):
        __read__
        return list(self._sources)

    def status(self):
        __read__
        return {"sources": len(self._sources), "interval": self._interval,
                "last_run": self._last_run}

    def run(self, progress=None):
        __run__
        self._running = True
        try:
            sources = list(self._sources.values())
            for done, source in enumerate(sources, start=1):
                self.store.write(source.name, source.fetch())
                if progress is not None:
                    progress(source.name, done, len(sources))
            self._last_run = time.time()
            __reset_ok__
        finally:
            __reset_finally__

swap(_m, "Syncer", Syncer)
'''
GUARDED = ("add_source", "remove_source", "rename_source", "set_interval", "clear", "run")
GOOD = dict({f"__{m}__": "self._idle()" for m in GUARDED},
            __read__="pass", __reset_ok__="pass", __reset_finally__="self._running = False")


def patch(**changes):
    src = TEMPLATE
    for key, value in dict(GOOD, **changes).items():
        src = src.replace(key, value)
    return src


MUTANTS = {f"{m}() is not guarded during run()": patch(**{f"__{m}__": "pass"}) for m in GUARDED}
MUTANTS["the syncer stays busy after a run that raised"] = patch(
    __reset_ok__="self._running = False", __reset_finally__="pass")
MUTANTS["reads raise SyncerBusy during run()"] = patch(__read__="self._idle()")


def check(workdir):
    return mutation.hidden(workdir, HIDDEN) + mutation.suite_catches(workdir, patch(), MUTANTS)


if __name__ == "__main__":
    mutation.main(check)
