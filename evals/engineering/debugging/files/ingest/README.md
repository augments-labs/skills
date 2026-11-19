# ingest

Imports nightly payment batches. A batch is a JSON-lines file, one record per
line, with `id`, `name`, `city`, `amount`, and `ts` (ISO 8601 with a UTC
offset).

```bash
python3 -m ingest fixtures/batch_ok.jsonl
```

The import is all or nothing: a record that cannot be parsed stops the batch
and nothing is imported. Rows go to the SQLite file named by `INGEST_DB`
(an in-memory database when it is unset).

## Tests

```bash
python3 -m unittest discover -s tests -t .
```
