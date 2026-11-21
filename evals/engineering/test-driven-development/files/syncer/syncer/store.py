class MemoryStore:
    def __init__(self):
        self.data = {}

    def write(self, source_name, records):
        self.data[source_name] = list(records)
