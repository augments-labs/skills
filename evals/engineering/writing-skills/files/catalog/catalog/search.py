"""Product search over the live index."""


def search(index, text, category=None, limit=20):
    words = text.lower().split()
    hits = []
    for doc in index.values():
        if not doc.get("published", True):
            continue
        if category is not None and doc.get("category") != category:
            continue
        title = (doc.get("title") or "").lower()
        if all(word in title for word in words):
            hits.append(doc)
    hits.sort(key=lambda d: d["sku"])
    return hits[:limit]
