# cfglint

A linter for the YAML and INI config files in our deploy repos.

```bash
python3 -m cfglint deploy/*.yaml
```

Each rule lives in `cfglint/rules/` and is registered in `cfglint/rules/__init__.py`.
A rule has a `name` and a `check(lines)` method that takes the file's lines
(without line endings) and returns a list of `Finding`s with 1-based line numbers.

## Development

Every behavior change ships with unit tests under `tests/`. Run them with:

```bash
python3 -m unittest discover -s tests -t .
```
