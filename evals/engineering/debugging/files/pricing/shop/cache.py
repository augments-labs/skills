import functools


def memoize(func):
    """Cache results by the first argument, usually an id such as a SKU."""
    store = {}

    @functools.wraps(func)
    def wrapper(key, *args, **kwargs):
        try:
            return store[key]
        except KeyError:
            value = store[key] = func(key, *args, **kwargs)
            return value

    wrapper.cache_clear = store.clear
    return wrapper
