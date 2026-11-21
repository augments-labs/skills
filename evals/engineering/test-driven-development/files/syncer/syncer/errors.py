class SyncError(Exception):
    """Base class for syncer errors."""


class UnknownSource(SyncError, KeyError):
    """No source by that name."""


class DuplicateSource(SyncError, ValueError):
    """A source by that name already exists."""
