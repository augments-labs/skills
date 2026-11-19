import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRATCH = ROOT / ".test-tmp"
DATA_NAME = "ledger.jsonl"


def scratch_ledger_path(name):
    """A ledger path in a new directory under .test-tmp/."""
    SCRATCH.mkdir(exist_ok=True)
    return Path(tempfile.mkdtemp(prefix=name + "-", dir=SCRATCH)) / DATA_NAME
