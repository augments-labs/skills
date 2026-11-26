# Fixing a bug

The `debugging` skill changes how your agent handles bug reports, failing or flaky tests, crashes, hangs, and wrong output. Instead of guessing at a patch from the first stack trace, the agent proves the root cause with a runnable signal first.

## When it loads (and when it skips)

`debugging` loads when something is broken and the diagnosis is left to the agent: a bug report, failing or flaky test, CI failure, regression after a merge or upgrade, memory leak, hang, or unexpected empty output.

It skips when you have already diagnosed the problem and spelled out the exact fix (such as a missing import, a typo, or a null check with a known fallback), during a live user-facing outage (contain first), and during post-incident reviews of an already-fixed bug.

## What the agent does differently

1. **Builds a fast reproduction first.** Before editing product code, the agent confirms it can reproduce the exact failure with a deterministic test or script. For timing or CI-only bugs, it loads `references/probabilistic-evidence.md` instead of assuming three passing local runs mean the bug is gone.
2. **Reverts failed earlier patches.** If someone already left speculative fix attempts in the code or branch, the agent strips them out first so it measures against a clean baseline.
3. **Inspects test doubles side by side with real code.** A common trap is a mock, fake, stub, or golden file that drifted from the real implementation. The agent compares the double's full public interface against the real class and adds a contract check covering both.
4. **Checks the actual failing records.** When a log file, export, or failed batch is readable, the agent tests against those exact records to catch secondary bugs hidden behind the first error.
5. **Searches for sibling sites.** After fixing one site, the agent checks parallel paths (such as sync and async clients, v1 and v2 handlers, or other readers of the same flag or cache) for the same root cause.
6. **Stops after three missed fixes.** If three applied fixes miss the mark, the agent stops patching and re-examines its reproduction, mental model, and layer instead of stacking guesses.

## Example prompts

Good prompts that let `debugging` do its job:

```text
tests/test_service.py started failing after yesterday's merge with an unexpected keyword argument error. Find the cause and fix it.
```

```text
Last night's import rejected fixtures/failed_batch.jsonl while other batches succeed. Fix the importer so this batch imports cleanly.
```

```text
test_unique_ids_under_load passes locally when I run it a few times, but fails in CI about one run in five. Track down why and fix it.
```

## What still depends on you

The skill stops and asks for your approval before running any probe or query against production, and before keeping logs or dumps that contain personal data, credentials, or secrets beyond the session.
