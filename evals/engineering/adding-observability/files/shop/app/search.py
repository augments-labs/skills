"""Product search."""
from app import api, catalog


@api.route("/search")
def search(query, backend=None):
    return (backend or catalog.backend).query(query)
