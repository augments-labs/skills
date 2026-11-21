# ledger

Double-entry bookkeeping service. Agent skills for this repo live in
`.agents/skills/`; agents load a skill there when its description matches the
task.

- `ledger/`: the service code.
- `migrations/`: SQL migrations, `NNNN_<slug>.up.sql` plus `NNNN_<slug>.down.sql`.
