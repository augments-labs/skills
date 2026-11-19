class IdAllocator:
    """Hands out increasing integer ids, persisted in a store under `key`."""

    def __init__(self, store, key="seq"):
        self.store = store
        self.key = key

    def next_id(self):
        current = self.store.get(self.key, 0)
        self.store.set(self.key, current + 1)
        return current + 1

    def last_id(self):
        return self.store.get(self.key, 0)
