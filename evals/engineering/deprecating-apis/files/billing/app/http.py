import re
from dataclasses import dataclass, field

ROUTES = []


@dataclass
class Response:
    status: int
    headers: dict = field(default_factory=dict)
    body: dict = field(default_factory=dict)


def route(method, pattern):
    regex = re.compile("^" + re.sub(r"<(\w+)>", r"(?P<\1>[^/]+)", pattern) + "$")

    def register(fn):
        ROUTES.append((method, regex, fn))
        return fn
    return register


def handle(method, path, headers=None):
    for m, regex, fn in ROUTES:
        match = regex.match(path)
        if m == method and match:
            return fn(headers or {}, **match.groupdict())
    return Response(404, {}, {"error": "no route"})
