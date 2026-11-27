"""Shipping address checks."""
import re


class AddressError(ValueError):
    pass


def validate(address):
    for field in ("name", "line1", "city", "postcode", "country"):
        if not str(address.get(field, "")).strip():
            raise AddressError(f"missing {field}")


def validate_strict(address):
    """The stricter check: also rejects malformed US ZIP codes and PO boxes."""
    validate(address)
    if address["country"] == "US" and not re.fullmatch(r"\d{5}(-\d{4})?", address["postcode"]):
        raise AddressError("bad ZIP code")
    if re.search(r"\bp\.?\s*o\.?\s*box\b", address["line1"], re.I):
        raise AddressError("PO boxes are not supported")
