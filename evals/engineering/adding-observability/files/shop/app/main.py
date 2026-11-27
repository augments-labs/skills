"""Build the service. Production calls create_app() once at startup."""
from app import api, checkout, search, webhooks  # noqa: F401  (registers routes)


def create_app():
    return api
