"""Exit 0 when list_products and GET /products page correctly, and the work tree's
own tests catch every planted paging bug (limit, limit+1, zero, page 0, partial
last page, past-the-end page, default size)."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "_mutation", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mutation.py"))
mutation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mutation)

HIDDEN = r'''
import sys
from decimal import Decimal
sys.path.insert(0, sys.argv[1])
from catalog.listing import list_products
from catalog.store import Product
from catalog.api import handle_list_products

P = [Product(f"S-{i:03d}", f"item {i:03d}", "tools" if i % 3 == 0 else "misc", Decimal(i))
     for i in range(1, 46)]
problems = []

def outcome(fn):
    try:
        return fn()
    except Exception as exc:
        return "raised " + type(exc).__name__

def expect(label, fn, want):
    got = outcome(fn)
    if got != want:
        problems.append(f"{label}: got {got!r}, want {want!r}")

def skus(rows):
    return [p.sku for p in rows]

def ids(a, b):
    return [f"S-{i:03d}" for i in range(a, b + 1)]

expect("45 products, default page_size", lambda: skus(list_products(P)), ids(1, 20))
expect("page=3 holds the 5 left over", lambda: skus(list_products(P, page=3)), ids(41, 45))
expect("page=4 is past the end", lambda: list_products(P, page=4), [])
expect("page_size=100", lambda: len(list_products(P, page_size=100)), 45)
expect("page_size=1, page=45", lambda: skus(list_products(P, page=45, page_size=1)), ["S-045"])
for bad in ({"page_size": 101}, {"page_size": 0}, {"page_size": -1}, {"page": 0}, {"page": -2}):
    expect(f"list_products({bad})", lambda: list_products(P, **bad), "raised ValueError")
expect("sorted before paging", lambda: skus(list_products(list(reversed(P)), page=2, page_size=5)), ids(6, 10))
expect("filtered before paging", lambda: skus(list_products(P, category="tools", page=2, page_size=10)),
       ["S-033", "S-036", "S-039", "S-042", "S-045"])
expect("empty catalog", lambda: list_products([]), [])

def api(query):
    status, body = handle_list_products(query)
    return status, [row["sku"] for row in body.get("products", [])]

expect("GET /products", lambda: api({})[0], 200)
expect("GET /products?page=2&page_size=3", lambda: api({"page": "2", "page_size": "3"}),
       (200, ["C-100", "C-200", "D-100"]))
expect("GET /products?page=9", lambda: api({"page": "9"}), (200, []))
for q in ({"page_size": "101"}, {"page_size": "0"}, {"page_size": "abc"}, {"page": "0"}, {"page": "x"}):
    expect(f"GET /products {q}", lambda: handle_list_products(q)[0], 400)
for p in problems:
    print("FAIL:", p)
sys.exit(1 if problems else 0)
'''

TEMPLATE = '''
import catalog.listing as _m
SORT_KEYS = {
    "name": lambda p: p.name.lower(),
    "price": lambda p: (p.price, p.name.lower()),
    "sku": lambda p: p.sku,
}
def list_products(products, *, category=None, in_stock_only=False, sort="name", page=1,
                  page_size=__DEFAULT__):
    if sort not in SORT_KEYS:
        raise ValueError(f"unknown sort key: {sort!r}")
    for value in (page, page_size):
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(f"page and page_size must be whole numbers, got {value!r}")
    if not (__SIZE_OK__):
        raise ValueError(f"page_size must be from 1 to 100, got {page_size}")
    if __PAGE_BAD__:
        raise ValueError(f"page must be 1 or more, got {page}")
    rows = [p for p in products
            if (category is None or p.category == category)
            and (not in_stock_only or p.in_stock)]
    rows = sorted(rows, key=SORT_KEYS[sort])
    start = (page - 1) * page_size
__SLICE__
swap(_m, "list_products", list_products)
'''
GOOD = {"__DEFAULT__": "20", "__SIZE_OK__": "1 <= page_size <= 100", "__PAGE_BAD__": "page < 1",
        "__SLICE__": "    return rows[start:start + page_size]"}


def patch(**changes):
    src = TEMPLATE
    for key, value in dict(GOOD, **changes).items():
        src = src.replace(key, value)
    return src


MUTANTS = {
    "page_size=100 is rejected": patch(__SIZE_OK__="1 <= page_size < 100"),
    "page_size=101 is accepted": patch(__SIZE_OK__="1 <= page_size <= 101"),
    "page_size=0 is accepted": patch(__SIZE_OK__="0 <= page_size <= 100"),
    "page=0 is accepted": patch(__PAGE_BAD__="page < 0"),
    "a partial last page after page 1 comes back empty": patch(__SLICE__=(
        "    if page > 1 and start + page_size > len(rows):\n        return []\n"
        "    return rows[start:start + page_size]")),
    "a page past the end raises": patch(__SLICE__=(
        "    if rows and start >= len(rows):\n        raise ValueError('page out of range')\n"
        "    return rows[start:start + page_size]")),
    "the default page_size is 50": patch(__DEFAULT__="50"),
}


def check(workdir):
    return mutation.hidden(workdir, HIDDEN) + mutation.suite_catches(workdir, patch(), MUTANTS)


if __name__ == "__main__":
    mutation.main(check)
