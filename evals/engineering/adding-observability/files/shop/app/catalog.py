"""Product catalog backend."""


class Backend:
    PRODUCTS = ["red mug", "blue mug", "tea kettle", "coffee grinder"]

    def query(self, text):
        words = text.lower().split()
        return [p for p in self.PRODUCTS if all(w in p for w in words)]


backend = Backend()
