# Demo-data hygiene — design

**Status:** approved for implementation planning
**Date:** 2026-07-24
**Queue position:** follow-up #3 of the "harden before expanding" round, after double-emit cleanup (PR #6, `fdff1cc`).

## Problem

`HealthGraphDebugView` (`#if DEBUG`) has four seed buttons — synthetic 400 days, mood 160 days, outside-factors 200 days, weather 200 days. All four write directly into the live Health Graph, the same database that holds real logged data. Six defects follow:

1. **Seeded rows are indistinguishable from real ones.** `EventSource` has no synthetic case; seeded symptoms are written `.manual` and seeded weather `.weatherAPI` — byte-identical in kind to real data. Nothing marks a row as fabricated.
2. **Event dedup keys collide with the real backfill.** `HealthGraphDebugView.swift:431` writes `DedupKey.daily(.environment, "temperature", dayStart:, provenance: .observedCompletedDay)` for the last 200 days — exactly the key the real observed-weather backfill produces for those days. Demo and real rows can overwrite each other in both directions.
3. **Object identity collides at the database level.** `health_objects` carries `t.uniqueKey(["normalizedName", "kind"])` (`AppDatabase.swift:48`) and `ObjectStore.swift:23` resolves objects by `normalizedName`. A seeded "Coffee" cannot coexist with a real "Coffee" of the same kind — it merges into it. Demo events then reference a real object, and a later cleanup either strands them or deletes an object the user actually owns.
4. **Cleared demo findings survive and stay visible.** `EvidenceEngine.recompute` never deletes relationships that lose support; it marks them `.decayed` (`EvidenceEngine.swift:157-162`). `InsightsFeed.swift:13-15` builds the Archive feed from precisely `.decayed` and `.userDismissed` rows, so fabricated findings remain on screen after their events are gone. Worse, the upsert at `:149` copies `firstSeen` from any prior row sharing an `edgeKey`, so a genuine relationship that later forms with the same key inherits the demo's date — which also drives the "New" ranking at `:19-22`.
5. **Seeds append.** A second tap silently doubles the dataset, so no device-gate run starts from a known state.
6. **The only escape deletes everything.** `eraseAllRows()` drops all events, objects, and relationships — real data included.

## Goals

1. **Real data on the user's own device survives a mis-tap**, and undoing a seed never requires deleting real data.
2. **Repeatable device gates** — a seed reloads to a known state instead of accumulating.
3. **Honest insights** — findings computed while fabricated data is present are never presented as trustworthy.

**Non-goal:** protecting other people's devices beyond the Release purge below. `#if DEBUG` already prevents seeding in shipped builds, and that is considered sufficient.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Mark with a `syntheticBatch` column, not a new `EventSource` case | Seeded rows must keep their real `source` values so they flow through identical code paths — that is what makes demo data useful for verifying real UI. A `.synthetic` source would change what every consumer sees. |
| 2 | Same-database marking, not a separate demo database file | Total isolation would forfeit the ability to test the mixed real+demo state, which is where today's dedup and unique-key collisions actually occur, and would touch every `HealthGraphProvider.shared` call site. |
| 3 | Namespace demo **event dedup keys** and demo **object identity** | Marking alone is insufficient: without namespacing, a demo row can replace a real row through dedup or the object unique key, and deleting the batch afterwards leaves a hole where real data used to be. |
| 4 | Hard-delete contaminated relationships; do not rely on decay | Decayed rows remain user-visible in the Archive feed and hijack `firstSeen` for genuinely-new findings. |
| 5 | Rebuild relationships wholesale rather than tracking per-edge provenance | Relationships are pure derived state, so a rebuild is exactly correct and needs no changes to `EvidenceEngine`'s internals. |
| 6 | Disable relationship dismissal while any demo batch is loaded | A demo card dismissed by the user would leave a `.userDismissed` row that later suppresses a genuine relationship sharing its `edgeKey`. Blocking dismissal during demo makes "preserve pre-existing dismissals" safe by construction. |
| 7 | Banner rather than per-card marking for insight honesty | Seeded days shift the engine's baselines, stability windows, and day counts, so relationships computed alongside demo data are contaminated too. Per-card chips would imply unmarked cards are clean when they are not. |
| 8 | Release builds purge synthetic rows at launch | Containers are shared by bundle ID, so a DEBUG-seeded database survives a Release install — where neither the clear button nor the banner exists. |
| 9 | Cleanup is one transaction; the caller's single recompute follows the commit | A partial cleanup that left contaminated relationships behind while the banner disappeared would present fabricated findings as clean. |
| 10 | Object namespacing needs a batch-aware find-or-create, not just a namespaced value on the generated object | `SyntheticDataset.insert` discards the generated object and rebuilds it inside `findOrCreate`, which recomputes `normalizedName` from the display name — so a namespaced value never reaches the database and the merge with real "Coffee" happens anyway. |
| 11 | The cleanup routine performs no recompute; callers run exactly one | A seed reload is delete-then-insert. Recomputing inside the routine would run a full pass over a knowingly-incomplete database, then a second pass after the insert. |
| 12 | The Release purge transaction runs synchronously at bootstrap; only its recompute is deferred | `AppDatabase` construction is synchronous and `recompute` is `async`. Deferring the relationship wipe as well would leave contaminated relationships readable — and rendering as ordinary findings — during startup. |
| 13 | Dismissal is gated in the view model as well as the UI | A card rendered before a seed completes can be tapped after it, and that stale-UI race writes exactly the `.userDismissed` row decision 6 exists to prevent. |

## Design

### 1. Marking

Migration **v7** adds a nullable `syntheticBatch TEXT` column to `health_events` and `health_objects`. `NULL` means real; existing rows need no backfill because they are real by definition. Both tables get a **partial index** on the column, conditioned `WHERE syntheticBatch IS NOT NULL`, so the index stays proportional to demo rows rather than to the whole table.

`HealthEvent` and `HealthObject` gain a matching `syntheticBatch: String?` property, defaulting to `nil`.

Batch identifiers, one per seed button: `"synthetic"`, `"mood"`, `"outsideFactors"`, `"weather"`.

### 2. Namespaced identity

**Events.** Demo dedup keys are prefixed `"demo:<batch>|"` ahead of the normal `DedupKey` value. A demo row can then never dedup-collide with a real row for the same day and subtype.

**Objects.** The user-facing `name` is unchanged — a demo card must still read "Coffee" — while `normalizedName`, which carries the unique key and drives `ObjectStore` lookup, is prefixed `"demo:<batch>|"` for seeded objects. Real and demo objects of the same name and kind then coexist as distinct rows, and the existing real-data dedup guarantee is untouched.

The prefix must be derived in exactly one place, and both the *lookup key* and the *persisted row* must use it. Today they cannot: `SyntheticDataset.insert` (`SyntheticDataGenerator.swift:89-90`) passes only `name`, `kind`, and `metadata` to `findOrCreate`, which recomputes `normalizedName` from the display name (`ObjectStore.swift:20`) and rebuilds the row via `HealthObject(kind:name:metadata:)` (`:28`). Any namespaced value on the generated object is discarded before it reaches SQLite, and the lookup at `:22-26` then matches the real "Coffee" and merges into it — the exact collision this section exists to prevent.

The design therefore requires a **batch-aware find-or-create path**: `findOrCreate` takes the batch, builds its lookup key through the same normalization helper that `HealthObject`'s initializer uses, filters on both the namespaced `normalizedName` and `syntheticBatch`, and persists a row carrying both. Because the helper is the single source of truth, the lookup key and the stored key cannot diverge.

This is deliberately not implemented by extending the unique key to include `syntheticBatch`: SQLite treats `NULL`s as distinct in unique indexes, so `unique(normalizedName, kind, syntheticBatch)` would permit two real rows with the same name and kind and silently destroy the invariant at `AppDatabase.swift:48`.

Object UUIDs are freshly generated per seed. Combined with delete-then-insert below, no identifier is reused across reloads.

`SyntheticDataGenerator` threads the batch through to every event and object it produces. Its batch parameter is **required, not defaulted**, so the compiler catches any future seeding path that forgets to mark its rows.

### 3. Seed lifecycle

Each seed button becomes delete-batch-then-insert: it removes its own batch's rows, then writes the fresh dataset. Two taps produce the same state as one. Batches remain independent, so weather and mood can be composed without either clearing the other.

A new **Clear demo data (keeps real data)** button removes every row with `syntheticBatch IS NOT NULL` across both tables. The existing *Reset Health Graph DB* button is unchanged — it remains the deliberate whole-database wipe.

### 4. Cleanup transaction

Every batch delete, batch reload, whole-demo clear, and the Release purge runs the same routine, parameterised by a scope that is either **one batch** (`syntheticBatch = '<batch>'`, used by seed reload) or **all batches** (`syntheticBatch IS NOT NULL`, used by the clear button and the purge). Inside **one transaction**, in this order:

1. Delete all `relationships` except those with `status == .userDismissed`. This step ignores the scope and is always total: relationships carry no batch attribution, and a single batch's events shift the statistics behind every edge, so a partial rebuild would be wrong.
2. Delete `health_events` matching the scope.
3. Delete `health_objects` matching the scope.

The order is dictated by the real foreign keys in the schema: `health_events.objectID` references `health_objects` with `onDelete: .setNull` (`AppDatabase.swift:59`), and relationships' object references cascade (`:77`, `:80`). Deleting events before objects prevents demo events from being stranded with a nulled `objectID`; deleting relationships first makes the cascade a no-op for them, and leaves it as a correct backstop for any dismissed row referencing a demo object.

**The routine does not recompute.** It performs the transaction and returns; each caller runs exactly **one** recompute at the end of its whole operation. A seed reload therefore recomputes once, after the replacement dataset is inserted — never once after the delete and again after the insert, which would burn a full pass over a knowingly-incomplete database.

Between the commit and that single recompute, the relationships table holds only pre-existing dismissed rows, so Insights renders empty. That is the required intermediate state, and it is also the required failure mode: if the recompute fails or never runs, Insights stays empty rather than showing stale demo findings as clean.

Real events that already reference a synthetic object — possible only for data seeded before this change — keep their rows and lose the object link, per the `setNull` rule. Real data is never deleted by any path here.

### 5. Dismissal gating

While any synthetic row exists, dismissal is unavailable — gated at **both** layers:

- **UI:** the Dismiss action is hidden or disabled on every card.
- **Model:** `InsightsViewModel.dismiss` (`:40-52`) and `undoDismiss` (`:54-60`) each re-check the database for synthetic rows and return without writing if any exist. The UI gate alone is insufficient — a card rendered before a seed completes can be tapped afterwards, and that stale-UI race is precisely what would write the `.userDismissed` row this rule exists to prevent.

Additionally, `pendingUndo` is cleared whenever demo data becomes present. Leaving it set would let an undo write a status onto a relationship id that the cleanup transaction has since deleted and the recompute has rebuilt under a new id.

Pre-existing `.userDismissed` rows are therefore always genuine user intent recorded against a clean database, which is what makes preserving them in step 4 safe rather than a compromise. In Release builds the purge guarantees no synthetic rows exist, so the gate never engages.

### 6. Insights banner

`#if DEBUG`. A single "any synthetic rows?" query drives a persistent notice at the top of Insights stating that demo data is loaded and the findings below — including ones derived from real data — are not trustworthy. The banner clears when the last batch is removed, which by step 4 cannot happen before the contaminated relationships are gone.

### 7. Release purge

Compiled into all configurations, active only in non-DEBUG builds. It delegates to the step-4 routine with the whole-demo scope.

Ordering is constrained by a shape mismatch: `AppDatabase` construction is **synchronous**, while `EvidenceEngine.recompute` is `async`, so the recompute cannot run during bootstrap. The split is therefore:

- **Synchronously, during bootstrap**, after migration and **before the provider yields a usable handle**: the whole purge transaction, *including the relationship wipe*. No reader — Insights, the Timeline, or a routine recompute — can observe the pre-purge state. This is possible because the transaction is a plain GRDB write with no `async` work inside it.
- **Once, scheduled after startup**: the recompute.

Until that recompute finishes, Insights is empty. That is safe; leaving the relationship wipe until after startup would not be, because contaminated relationships would then be readable — and would render as ordinary findings — in the window before the purge completed.

## Testing

**HealthGraphCore**

- v7 migration against a populated pre-v7 database: existing rows survive, the column exists, and every pre-existing row reads `nil`.
- Both partial indexes exist and are conditioned on `syntheticBatch IS NOT NULL`.
- Deleting one batch removes that batch's events and objects only, leaving real rows and other batches intact.
- A demo dedup key and the real key for the same day and subtype are never equal.
- A demo object sharing a real object's display name and kind inserts without violating the unique key, and the real object's row is unchanged.
- **Seeding through `SyntheticDataset.insert` against a database that already holds a real object of the same name and kind creates a second, batch-scoped row and leaves the real object's `id` and `normalizedName` untouched** — the regression test for the discarded-namespacing defect. Its events reference the demo object's id, not the real one.
- Cleanup clears every relationship except `.userDismissed`, and a failure partway through rolls the whole transaction back.
- The cleanup routine performs no recompute of its own.
- The purge removes synthetic rows and is a no-op on a database with none.

**App**

- The banner is visible exactly when synthetic rows exist.
- Dismissal is unavailable while demo data is loaded, **at the view-model layer specifically**: calling `dismiss` directly while synthetic rows exist writes nothing, as does `undoDismiss`.
- `pendingUndo` is cleared when demo data becomes present.
- Tapping a seed button twice leaves the row count unchanged from one tap, and performs one recompute per tap.

## Accepted limitation — legacy demo rows

Rows seeded **before** this change carry no batch marker, and no migration can retroactively identify them.

**No heuristic cleanup pass will be implemented.** The only signals available — object names like "Coffee" or "Magnesium", and dedup keys matching the real backfill's format — are identical to real data *by construction*: the seeds were written to imitate real rows, which is the defect this design corrects. Any best-effort pass would therefore delete genuine user rows some of the time, violating goal 1, the primary safety goal. A wrong deletion is unrecoverable; a manual reset is not.

**Required one-time action.** A database already contaminated by earlier demo taps must be cleared once with *Reset Health Graph DB* to reach a clean baseline. This deletes all events, objects, and relationships, real data included — so it should be done deliberately, on a device whose real data is either expendable or re-importable from HealthKit. After that single reset, every subsequent seed is precisely and safely removable, and no further reset is ever required.

Until that reset is performed, the banner still behaves correctly for *newly* seeded batches, but legacy rows remain invisible to it: they carry no marker, so a database holding only legacy demo data shows no banner and reports itself clean.
