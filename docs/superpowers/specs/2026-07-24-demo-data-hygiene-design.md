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
| 9 | Cleanup is one transaction, recompute follows the commit | A partial cleanup that left contaminated relationships behind while the banner disappeared would present fabricated findings as clean. |

## Design

### 1. Marking

Migration **v7** adds a nullable `syntheticBatch TEXT` column to `health_events` and `health_objects`. `NULL` means real; existing rows need no backfill because they are real by definition. Both tables get a **partial index** on the column, conditioned `WHERE syntheticBatch IS NOT NULL`, so the index stays proportional to demo rows rather than to the whole table.

`HealthEvent` and `HealthObject` gain a matching `syntheticBatch: String?` property, defaulting to `nil`.

Batch identifiers, one per seed button: `"synthetic"`, `"mood"`, `"outsideFactors"`, `"weather"`.

### 2. Namespaced identity

**Events.** Demo dedup keys are prefixed `"demo:<batch>|"` ahead of the normal `DedupKey` value. A demo row can then never dedup-collide with a real row for the same day and subtype.

**Objects.** The user-facing `name` is unchanged — a demo card must still read "Coffee" — while `normalizedName`, which carries the unique key and drives `ObjectStore` lookup, is prefixed `"demo:<batch>|"` for seeded objects. Real and demo objects of the same name and kind then coexist as distinct rows, and the existing real-data dedup guarantee is untouched.

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

After the transaction commits, `EvidenceEngine.recompute` runs. If it fails, the relationships table holds only pre-existing dismissed rows, so Insights renders empty — the required failure mode. Stale demo findings must never remain on screen once the banner is gone.

Real events that already reference a synthetic object — possible only for data seeded before this change — keep their rows and lose the object link, per the `setNull` rule. Real data is never deleted by any path here.

### 5. Dismissal gating

While any synthetic row exists, the dismiss action in `InsightsViewModel` (`:44-49`) is unavailable. Pre-existing `.userDismissed` rows are therefore always genuine user intent from a clean database, which is what makes preserving them in step 4 safe. In Release builds the purge guarantees no synthetic rows exist, so the gate never engages.

### 6. Insights banner

`#if DEBUG`. A single "any synthetic rows?" query drives a persistent notice at the top of Insights stating that demo data is loaded and the findings below — including ones derived from real data — are not trustworthy. The banner clears when the last batch is removed, which by step 4 cannot happen before the contaminated relationships are gone.

### 7. Release purge

Compiled into all configurations, active only in non-DEBUG builds. It runs during database bootstrap, after migration and **before the provider yields a usable handle**, so no reader — Insights, the Timeline, or a routine recompute — can observe the pre-purge state. It delegates to the step-4 routine with the whole-demo scope.

## Testing

**HealthGraphCore**

- v7 migration against a populated pre-v7 database: existing rows survive, the column exists, and every pre-existing row reads `nil`.
- Both partial indexes exist and are conditioned on `syntheticBatch IS NOT NULL`.
- Deleting one batch removes that batch's events and objects only, leaving real rows and other batches intact.
- A demo dedup key and the real key for the same day and subtype are never equal.
- A demo object sharing a real object's display name and kind inserts without violating the unique key, and the real object's row is unchanged.
- Cleanup clears every relationship except `.userDismissed`, and a failure partway through rolls the whole transaction back.
- The purge removes synthetic rows and is a no-op on a database with none.

**App**

- The banner is visible exactly when synthetic rows exist.
- Dismissal is unavailable while demo data is loaded.
- Tapping a seed button twice leaves the row count unchanged from one tap.

## Accepted limitation

Rows seeded **before** this change carry no batch marker, and no migration can retroactively identify them — distinguishing them from real data would require heuristics on names and dedup keys that risk deleting genuine rows. A database already contaminated by earlier demo taps therefore needs one full *Reset Health Graph DB* to reach a clean baseline, after which every subsequent seed is precisely removable.
