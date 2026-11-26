# Writing tests first

The `test-driven-development` skill pushes your agent to write tests that actually break when the behavior breaks, rather than writing green tests after the implementation that just restate the code.

## When it loads (and when it scales down)

`test-driven-development` loads when a task adds behavior with several rules, limits, or edge cases (a new feature, endpoint, validator, guard, or lock) or refactors, splits, moves, or rewrites code whose observable output must stay the same.

It scales down or skips on small work:

- Pure docs, comments, renames, formatting, or moving files unchanged: runs the existing suite and stops.
- One-condition tweaks (one extra bound, status code, or allowed value): adds one test in the same pass as the code without a separate red run or planted-bug pass.
- Unknown bug reports: leaves those to `debugging`.

## What the agent does differently

1. **Lists cases from the contract before writing tests.** Instead of mirroring the code it plans to write, the agent maps out boundaries (value at the limit and one past it), defaults, multiple occurrences in one input, every state-changing method covered by a guard, error paths that must release locks or leave state untouched, and near-miss inputs for detectors or linters.
2. **Watches new tests fail for the right reason.** An import error or missing function name does not prove a test works. The agent runs the suite against a stub or unchanged code and checks that each new test fails at its actual assertion. If a brand-new test passes before the feature exists, the agent fixes the test or shared assertion helper first.
3. **Pins existing behavior before refactors.** When refactoring working code, the agent reads every observable decision (rounding rules, tie order, case handling, empty inputs, duplicate precedence), captures expected outputs by running the original code, and temporarily flips each decision in the original code to confirm the characterization tests actually catch a change.
4. **Plants likely bugs before reporting done.** For multi-rule behavior, the agent plants common mistakes one by one (moving a boundary by one, dropping a guard, skipping a reset on error, stopping a loop after the first match), confirms the suite fails on each, restores the code, and adds a test for any mistake the suite missed.

## Example prompts

```text
Add pagination to list_products with page (1-based, default 1) and page_size (default 20, max 100), raising ValueError for out-of-range inputs and returning 400 on GET /products for bad values.
```

```text
Refactor summarize() in reports/summary.py into smaller functions. Finance reconciles against this output, so behavior must stay identical for every input.
```

```text
Add a SlidingLimiter(limit, window) class to quota/limiter.py with the same allow(key, now) interface as FixedLimiter, where denied calls do not count and keys are independent.
```
