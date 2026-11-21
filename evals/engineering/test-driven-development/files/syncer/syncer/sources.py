class Source:
    """A named upstream. Subclasses implement fetch() -> list of records."""

    def __init__(self, name):
        self.name = name

    def fetch(self):
        raise NotImplementedError


class StaticSource(Source):
    def __init__(self, name, records):
        super().__init__(name)
        self.records = list(records)

    def fetch(self):
        return list(self.records)
