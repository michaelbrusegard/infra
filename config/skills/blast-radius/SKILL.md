---
name: blast-radius
description: Find what a change could break beyond its diff and prove the fact its safety depends on. Use for blast-radius analysis, regression-risk review, or a small change whose hidden effects are unclear.
---

# Blast radius

Find what a change breaks somewhere else before it ships. Listing callers is
not the job. The job is the breakage a symbol search will not show.

## Do not trust the writeup

A convincing risk analysis can still be wrong. Find the one or two facts the
change's safety depends on and prove them by running the real code. Words are
where the investigation starts, not where it ends.

For every safety fact, get as far down this ladder as is cheap and say where it
stopped:

1. An assertion with no evidence. Worthless alone.
2. A pointer to the relevant `file:line` or dependency source.
3. A step-by-step demonstration that the bad case cannot reach the changed path.
4. A script or test that calls the real code and fails loudly when the fact is
   false.
5. A reproduction in the running application.

Mark any safety fact that does not reach step 4 as unproven. Do not round it up
to settled.

## Steps

1. Read the full change and state what it now does differently, including
   behavior the diff does not spell out.
2. Find the one fact it is safe because of. Spend more time on this than on a
   long list of hypothetical risks.
3. Look where search stops. Read the pinned dependency source and local patches.
   Follow timing, teardown, wire formats, schemas, stored data, other languages,
   feature flags, generated consumers, and code several hops downstream.
4. Give each risk a real likelihood and cost. Keep confirmed risks separate
   from important cases that were checked and cleared. Cite real evidence and
   treat a search that found no consumers as a finding.
5. Prove the safety fact with the smallest faithful script, test, or running-app
   reproduction. Paste the result. If proof is not cheap, mark it unproven and
   say what would prove it.
6. For a wide change, seek independent coverage from another reviewer when the
   harness and task authorization permit it, then reconcile disagreements
   against evidence.

## What to hand back

- **What it does.** The changed behavior, including the non-obvious part.
- **The safety fact.** The fact, its proof-ladder level, and the evidence, or
  `unproven`.
- **Risks.** Only real risks. State the failure, `file:line`, likelihood, cost,
  and check.
- **Cleared.** Important cases checked and why they are safe.
- **Before merge.** The cheapest test or reproduction that catches the real
  bug.

Write the result through `unslop`, cite real code, and remove private context
before anything public.
