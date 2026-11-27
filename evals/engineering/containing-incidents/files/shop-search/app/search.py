"""Product search."""
PRODUCTS = ["red mug", "blue mug", "tea kettle", "coffee grinder"]


def search(query):
    q = query.split()
    return [p for p in PRODUCTS if all(w in p for w in q)]
