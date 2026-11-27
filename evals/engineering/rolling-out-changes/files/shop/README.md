# shop

The order service behind the storefront: quotes, checkout, confirmation
emails, and a few background jobs.

## Layout

- `app/api.py`: request handlers for quotes and checkout
- `app/orders.py`: placing orders and sending confirmations
- `app/pricing.py`: subtotal and shipping
- `app/jobs.py`: background jobs (confirmation retries, saved-cart repricing, weekly digest)
- `app/recs.py`: product recommendations from the vendor API
- `app/address.py`: shipping address checks
- `app/flags.py`: feature flags
- `app/metrics.py`, `app/cache.py`, `app/notify.py`: shared plumbing

## Feature flags

Flags are read through `app.flags.is_enabled(name, subject=None)`. A flag is
either `true`/`false` or `{"percent": N}`, which turns it on for N% of
subjects (pass a stable id such as the customer id so a customer stays in the
same group). A flag that is not set is off.

In production, `FLAGS_FILE` points at the file the flag service keeps in sync.
Ops change flags there, and every running process sees the change on its next
call, without a restart or deploy. `config/flags.json` is only the local
default.

## Rollouts

Every rollout is watched on the checkout dashboard, which graphs
`checkout.completed` and `checkout.failed` from `app.metrics`.

## Tests

```
python3 -m unittest discover -s tests -t .
```

Keep changes small and seperate from unrelated cleanups.
