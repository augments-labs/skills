# humanize

Human-readable strings for the mobile and web clients.

- `humanize/duration.py`: `describe(seconds)` turns an elapsed time into text
  such as `2 hours and 5 minutes`.
- `humanize/sizes.py`: `file_size(n)` turns a byte count into text.

## Development

Every behavior change ships with unit tests under `tests/`. Run them with:

```bash
python3 -m unittest discover -s tests -t .
```
