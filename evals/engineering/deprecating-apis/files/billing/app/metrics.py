EVENTS = []


def emit(name, value=1, **labels):
    EVENTS.append((name, value, labels))
