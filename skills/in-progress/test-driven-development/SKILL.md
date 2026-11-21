---
name: test-driven-development
description: "Writes tests that fail when the behavior they cover breaks, before the code that makes them pass. Load it before your first edit when a task adds behavior with several rules or cases to get right (a feature, component, endpoint, parameter, rule set, validation, guard, or lock) or refactors, splits, moves, or rewrites code whose output must not change. Skip it for a one-condition tweak to existing code (one more bound, code, or allowed value), docs, comments, renames, formatting, config values, and bug reports whose cause is still unknown."
---

# Test-driven development

A test is worth keeping only if it fails when the behavior it covers breaks.
Write it before the code, watch it fail for the reason you expect, and before
you report done, show that the suite catches each rule going wrong. A green
suite on its own proves only that the tests ran.

## When to skip or scale down

- Nothing observable changes (docs, comments, renames, formatting, moving
  code without editing it): run the existing suite and stop.
- A one-condition change (one more bound, code, or allowed value): add or
  extend one test in the same pass as the code and run the suite once. No
  separate red run, no planted bugs.
- The user asked for a throwaway spike or for no tests.

## Step 1: List the cases before the first test

Build the list from the request and the code's existing contract, not from
the implementation you have in mind:

- **Limits:** for each stated limit, the value at the limit and one past it,
  at both ends of a range. "At least N" needs exactly N, N - 1, and well
  over N; an example of exactly N alone lets "exactly N" pass.
- **Defaults:** a test that omits the argument, with enough data that a
  different default would change the result.
- **Each, every, any:** two or more occurrences in one input (two matches on
  one line, the second item over the limit), not just one.
- **Sets of members:** when a rule covers every method that changes state,
  every field, or every endpoint, one case per member. Take the members from
  the code, not from the misuse you expect, and include a nested call of the
  guarded operation itself.
- **Failure paths:** a rejected call leaves state unchanged; a flag, lock, or
  resource is released when the operation raises partway.
- **Detectors** (lint rules, validators, scanners, parsers): each flagged
  form and the near-misses closest to it (the allowed variant, one character
  short, the bare prefix).
- **Edges:** empty input, a position past the end, the partial last chunk,
  and data where filter, sort, and paging order would show.

Test only what the request or the existing contract pins. An assertion on a
message, type, or format nobody specified fails a correct implementation.

## Step 2: Red, then green

1. Write the tests for the list. Assert errors with the framework's own
   construct, or through a helper you have watched fail.
2. Run them through the project's test command before writing product code.
   Each new test must fail at its assertion. An import error or a missing
   name is not red for the behavior: add a stub that returns a wrong value
   and rerun.
3. A new test that passes before the code exists is broken until shown
   otherwise. Either the behavior already exists, the assertion cannot fail,
   or a shared helper swallows the failure (an `except` that also catches
   the assertion error, a check that returns early). Fix the test or the
   helper first.
4. Write the code that makes them pass. Run the new tests, then the whole
   suite.

## Step 3: Refactors pin the behavior first

When the change must keep behavior (refactor, split, move, rewrite, port):

1. Read the code you will change and list every decision that shows in its
   output: inputs it skips or special-cases, sign changes, where and how it
   rounds (the mode, and per item or on the total), sort and tie order, case
   and whitespace handling, which duplicate wins, placeholder values, results
   for empty input, and errors.
2. For each decision, write a characterization test whose input would give a
   different output if the decision changed. For rounding, pick values that
   land exactly on a half and parts that only add up when summed; for ties,
   equal keys first seen in an order no other sort would give (not
   alphabetical, not by id); for "first wins", two spellings.
3. Run them on the unchanged code and see them pass. Take expected values
   from running the original, not from reading it.
4. Prove each one guards its decision: change that decision in the original
   (flip the rounding mode, break ties another way, drop the case fold), run,
   see a test fail, and restore. A change that stays green needs a better
   test.
5. Refactor in small steps, running the suite after each.

## Step 4: Plant the bugs the tests exist for

For new behavior with more than one rule, before you report done:

1. List the mistakes most likely for this change: each boundary moved by
   one, each rule or guard dropped, the reset skipped on the error path, a
   loop that stops after the first match, a different default.
2. Plant each one in your implementation, run the suite, and confirm it
   fails. Restore the code after each.
3. A planted mistake the suite misses is a missing test. Add it, see it fail
   against the mistake, restore, and rerun.
4. Finish with the diff showing only the intended changes and the whole
   suite green.

## Before you report done

Confirm each with output from this session:

- Every case on the list has a test, and each new test failed before its
  code existed (or, for a refactor, failed against a planted change).
- Every planted mistake made the suite fail, and the code is back to the
  intended version.
- The project's full test command exits 0, and you read its output.

## Gotchas

- Tests written after the code tend to restate it. A test you never saw fail
  may pass for any implementation.
- A shared assertion helper is code too. If new tests built on it never
  fail, suspect the helper.
- Guards and flags break on the path nobody tests: the member added last,
  the nested call, the reset after an exception.
