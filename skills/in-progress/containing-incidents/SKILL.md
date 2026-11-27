---
name: containing-incidents
description: "Contains a live production problem that is hurting users now: errors, outages, slowness, wrong charges, or bad data being written. Load it before the first command when asked to handle, mitigate, or respond to an active alert or incident. Skip it for bugs with no live impact, postmortems, and questions about past incidents."
---

# Containing incidents

While users are failing, your job is to stop the harm, not to find the bug.
Contain first, with the smallest change you are allowed to make, prove it
worked from what users see, then hand the cause to normal work.

## 1. Read what users see

Start from the external signal: status checks, synthetic probes, edge error
rates and latency, support reports. Note when it started and what changed
around then: flag rollouts, deploys, jobs, config, traffic from one client.
Do not read or edit product code yet. A code fix cannot reach users until a
review and deploy, and the users are failing now.

## 2. Know what you may do alone

Find the runbook or on-call guide before you pull anything. Having the
credentials or the command is not permission. Unless the runbook says
otherwise, these always wait for the incident commander or owner, even when
they would work:

- deploys and rollbacks;
- changes to production data: refunds, deletes, edits, replays, backfills;
- blocking or suspending a customer, account, or key;
- anything you cannot undo in a second.

Page or ask for those, say exactly what you propose and why, and keep
containing with what you may do while you wait. Never edit production state
behind the tool that records it.

## 3. Pull the narrowest lever

Choose the smallest reversible switch that stops new harm:

- turn down the flag of the feature that is failing, not every flag;
- pause the job doing damage, not the whole queue;
- cap the one client flooding the system, rather than block it or everyone;
- purge the cache that holds bad entries.

Stop new harm before repairing old harm. Repair (refunds, data fixes,
replays) is a decision for the owner, with the numbers you collected.

## 4. Prove recovery from the same signal

After each lever, re-read the signal you started from. Do not trust that the
lever should have worked. If the signal is not back to its baseline, read the
new top error: a first lever often leaves a second cause, such as cached
results, queued work, another region, or a second flag. Declare it contained
only when the signal shows it.

## 5. Keep evidence, not secrets

Save what the owner will need: error lines, timestamps, counts, and every
command you ran. Logs carry tokens, card numbers, emails, and other personal
data. Redact them before anything leaves the logs: notes, tickets, chat, or
your reply.

## Report

- Impact: who was affected, from when, and how many.
- What you did, in order, and its cost (what is now off, for whom).
- The current signal, with the numbers.
- What waits for approval, and what you asked for.
- The suspected cause and the evidence for it, for follow-up after containment.
