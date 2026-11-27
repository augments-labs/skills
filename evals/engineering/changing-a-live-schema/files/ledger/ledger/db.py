"""PostgreSQL connections."""


def connect(url):
    import psycopg

    return psycopg.connect(url)
