# Insights N+1 — design

**Date:** 2026-08-25
**Status:** approved, pending implementation plan
**Scope:** move `InsightsViewModel.load()` onto the batch evidence API. Nothing else.

---

## The measurement that closed the question

`load()` calls `engine.evidence(for:)` once per active card, and **each call reads the
entire event corpus** (`events(in: .distantPast ... .distantFuture)`). `evidenceReports(for:)`
does one read for all of them. Profiled 2026-08-25:

| Corpus | Active cards | Per-card | Batched |
|---|---|---|---|
| 3,357 | 10 | 0.62s | 0.07s |
| 7,809 | 11 | 1.51s | 0.16s |
| **38,000 (real device)** | **10** | **~6.9s** (extrapolated) | **~0.7s** |

Cost is linear in corpus × cards — 18.5 µs and 17.6 µs per event-card across a 2.3×
difference in corpus size, so the extrapolation holds.

The original deferral said "unless profiling shows it blocks backfill". The real shape is
worse than that framing: it is ~7 seconds of work every time the Insights tab appears, and
it grows with the two quantities the app exists to increase — imported history and
discovered relationships. It has gone unnoticed only because a real graph currently has
**zero active relationships**, so the loop body never runs. The cost switches on exactly
when the app starts working.

## The change

One call. `load()` gathers the active relationships, calls
`engine.evidenceReports(for:asOf:)` once, and reads each card's evidence from the returned
dictionary. Failure behaviour is unchanged: the batch path already fails soft per edge, and
a missing entry yields the same empty dot row a failed `evidence(for:)` call did.

Incidental improvement, worth naming: `asOf: now()` was evaluated once per card and is now
evaluated once, so every card in a render is dated from the same instant.

## Explicitly not in scope

- **The per-row object lookup** in `exposure(for:)`. It is a second query per row, but an
  indexed fetch by primary key — microseconds against the ~690ms per call the profile
  measured. Batching it means new store API for something the profile does not show as hot.
- **The `relStore.all()` fetch.** `load()` resolves all relationships, not just active ones,
  and the non-active ones feed other feed sections. Narrowing it would change what the feed
  contains — a behaviour change dressed as a performance fix.

## Testing

The risk in a performance fix is silently changing what is displayed, so the tests are about
equivalence first and speed second.

- The nine existing `InsightsViewModelTests` must pass **unchanged**. The feed's contents are
  the contract.
- **A call-count test, not a timing test.** `InsightsViewModel` already takes an injectable
  `hasSyntheticData` closure, so the same pattern extends to evidence: inject a recording
  provider, and assert it is called **exactly once** for a feed with several active cards.
  That is the deterministic form of "stays batched" — a timing threshold would be flaky on
  CI and would not say what actually regressed.
- **Mutant:** revert `load()` to a per-card loop and confirm the call-count test fails. If it
  does not fail, the test is theatre.

The injectable provider is the one structural addition, and it follows the file's own
existing precedent rather than introducing a new idea.
