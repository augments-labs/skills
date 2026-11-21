"""Index mapping and the incremental indexer.

Mapping changes only apply to a freshly built index (see the LAMPLIGHT
runbook); the incremental indexer patches documents in the live index.
"""

MAPPING = {
    "sku": {"type": "keyword"},
    "title": {"type": "text", "analyzer": "english"},
    "brand": {"type": "keyword"},
    "category": {"type": "keyword"},
    "price_cents": {"type": "integer"},
    "published": {"type": "boolean"},
}


def to_document(product):
    """Shape a product row into an index document."""
    return {field: product.get(field) for field in MAPPING}


def apply_event(index, event):
    """Patch the live index from one change event. No replay: a dropped
    event stays wrong in search until a full rebuild."""
    sku = event["sku"]
    if event["kind"] == "delete" or not event["product"].get("published", True):
        index.pop(sku, None)
    else:
        index[sku] = to_document(event["product"])
