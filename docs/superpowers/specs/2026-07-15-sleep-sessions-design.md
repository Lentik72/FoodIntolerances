# Sleep-Session Summarization — Design

**Date:** 2026-07-15
**Status:** Approved (decisions made interactively with Leo)
**Depends on:** Phase 1B Timeline (`TimelineDayBuilder`, `TimelineEventRow`, keyset pagination), Phase 1A ingestion (`.sleep` stage events)
**Scope:** Timeline presentation feature + capture-chip affordance polish. No schema change, no migration, no ingestion change.

## 1. Problem

Each HealthKit sleep-stage segment is stored as its own `HealthEvent` (category `.sleep`, subtype `inBed` / `awake` / `asleepCore` / `asleepDeep` / `asleepREM` / `asleepUnspecified`, value = duration minutes, `timestamp`/`endTimestamp` set). A real night is 20–60+ segments, so the Timeline renders a wall of "Core sleep 24m / Awake 2m / REM 12m" rows. Worse, the day-builder groups by start timestamp, so a night straddling midnight splits across two day sections.

Secondary: the quick-log chips in the capture sheet (neutral capsule, card fill, secondary ink) read as static tags, not buttons — checkpoint feedback from 1C.

## 2. Decisions (Leo, 2026-07-15)

| Decision | Choice |
|---|---|
| Architecture | **Display-time builder** — pure function in HealthGraphCore; raw events untouched; nothing materialized |
| Day a night belongs to | **Wake-up day** (`startOfDay(session.end)`), matching Apple Health / Oura convention |
| Row interaction | **Inline expand/collapse** — no navigation push, no raw-segment drill-down |
| Session split threshold | **≥ 60-minute hole in sleep data** starts a new session; recorded `awake` segments never split |
| Chip affordance | **Accent-tinted capsule** — accent text, ~12% accent wash, hairline accent border, pressed-state dim |

Rejected: materialized `sleepSession` events at ingestion (derived data in a durable append-only graph needs deterministic session identity, recompute/upsert for late-arriving segments, and a backfill over ~136k events — heavy machinery for presentation); Home-card-only (loses sleep-in-context between evening meal and morning symptoms).

## 3. Data model (HealthGraphCore, new file `Timeline/SleepSessionBuilder.swift`)

```swift
public struct SleepSession: Equatable, Sendable, Identifiable {
    public let start: Date              // earliest segment start (bed time)
    public let end: Date                // latest segment end (wake time)
    public let kind: Kind               // .night | .nap
    public let coreMinutes: Double
    public let deepMinutes: Double
    public let remMinutes: Double
    public let unspecifiedMinutes: Double
    public let awakeMinutes: Double
    public let inBedMinutes: Double
    public let segmentCount: Int
    public var asleepMinutes: Double    // core + deep + rem + unspecified
    public var id: String               // deterministic from span, e.g. "sleep-<start epoch>-<end epoch>"
    public enum Kind: Sendable { case night, nap }
}
```

Sessions are display-time values — no stored UUID, no DB row, no relationship edges.

## 4. Session detection (`SleepSessionBuilder.sessions(from:timeZone:)` — pure)

1. Input: any slice of `HealthEvent`s; the builder filters to `category == .sleep` itself. **Sub-minute segments count** — the existing ≥60s row filter is display-only and must not starve the totals.
2. Sort ascending by `timestamp`. Chain overlap-aware: a segment joins the current session if its start is ≤ 60 minutes after the furthest `endTimestamp` seen so far in that session; otherwise a new session begins. Only a genuine gap in the *data* splits — a recorded 45-minute 4 AM `awake` segment keeps the night whole (it extends the chain).
3. Totals: sum duration per subtype into the stage buckets. `inBed` is tracked separately and **never** added to `asleepMinutes` (it overlaps the stages). Stages-without-inBed is normal (Watch). InBed-only (phone-only users) yields a session with `asleepMinutes == 0` — displayed as "In bed" with no breakdown.
4. Classification: `.nap` iff `asleepMinutes < 180` **and** the session starts at/after 06:00 **and** ends at/before 21:00 in the passed `timeZone`; else `.night`. (A 2 h crash-sleep starting 1 AM is a night.) An inBed-only session classifies by the same rule using `inBedMinutes` in place of `asleepMinutes`.
5. Day assignment and ordering are the caller's job (see §5); the builder just returns sessions sorted ascending by `end`.

Timezone rule: day assignment and nap classification use the single `timeZone` passed in (consistent with existing day grouping). Per-segment `timezoneID` stays untouched in the raw data for future travel-aware work.

## 5. Timeline integration

**`TimelineItem`** (new, in `TimelineDayBuilder.swift`): two-case enum `.event(HealthEvent)` / `.sleepSession(SleepSession)`, `Identifiable`, `Equatable`, `Sendable`. Sort key: event → `timestamp`, session → `end` (the wake moment), merged newest-first, ties broken by id for determinism.

**`TimelineDay`**: `events: [HealthEvent]` becomes `items: [TimelineItem]`. `severityPoints` unchanged (still built from symptom events).

**`TimelineDayBuilder.days(from:timeZone:sessionizeSleep:)`**:
- `sessionizeSleep: true` (browse): `.sleep` **duration** events leave the row stream entirely; `SleepSessionBuilder` folds them into sessions, each bucketed under `startOfDay(end)` — the wake-up day. A session row can therefore live in a different day bucket than some of its segments started in; that is the point. Point `.sleep` events (no `endTimestamp` — the mapper never emits them, but manual/synthetic data can) pass through as raw rows.
- `sessionizeSleep: false` (search): raw rows as today. Search results are a filtered subset (e.g. matching "REM"); sessionizing a subset would show wrong totals. FTS and search behavior are unchanged.
- The existing ≥60s duration-row filter still applies to *displayed raw* duration events (non-sleep, and sleep in search mode); sleep segments feeding the session builder bypass it.

**`TimelineViewModel`**:
- Browse/paging paths call the builder with `sessionizeSleep: true`; `runSearch()` with `false`.
- `delete()` / `undoDelete()`: the current surgical per-day rebuild is invalid (a session's segments can span day buckets), so both rebuild `days` from the full remaining `browseEvents` slice — same O(n log n) work the pager already does per page, on ≤ a few thousand loaded events.
- Sessions are not deletable/editable/navigable rows; only `.event` items push `EventDetailView`. Raw sleep segments remain reachable (and deletable) through search.

**Pagination boundary artifact (accepted):** the oldest loaded page can cut a night mid-session, so that one row shows partial totals until the next page loads and days rebuild. Identical in kind to today's partially-loaded day; self-heals on scroll. No mitigation UI.

## 6. Presentation

**`SleepSessionRow`** (new view beside `TimelineEventRow`):
- Collapsed: day-spine gutter with the 28pt duration tick, `CategoryStyle` sleep icon/color, title **"Sleep · 7h 32m"** / **"Nap · 42m"** / **"In bed · 8h 02m"** — the title duration is `asleepMinutes` (`inBedMinutes` for inBed-only sessions), formatted via `EventDisplay.durationString`, NOT the bed→wake span. Right side shows the **bed→wake range** ("11:24 PM – 7:03 AM") where other rows show a single time. Chevron signals expandability.
- Expanded (tap toggles, animated): slim proportional stacked bar ordered **Deep · Core · REM · Awake** — opacity ramp of the sleep family color, Awake in neutral ink-muted — then one line per non-zero stage with its duration. Zero-duration stages and the bar are omitted for inBed-only sessions.
- Expansion state: `@State private var expandedSessions: Set<String>` in `TimelineView`, keyed by session id; resets on reload (fine).
- Accessibility: collapsed row is one element — "Sleep, 7 hours 32 minutes, 11:24 PM to 7:03 AM", hint "Expands stage breakdown", `.isButton` trait; expanded stage lines individually readable; the bar is decorative (`accessibilityHidden`). 44pt targets, Dynamic Type, HealthTheme tokens only, no raw colors, no causal language.

**Chip affordance polish:** the three duplicated private `chip()` helpers in `SymptomCaptureView` / `MealCaptureView` / `DoseCaptureView` consolidate into one shared `QuickLogChip` component (HealthOS theme/components area): accent-colored label, `HealthTheme.accent` wash at ~12% opacity, hairline accent border, pressed-state dim via a small custom `ButtonStyle`, `minHeight: 44` and a11y labels preserved. Pure restyle; behavior, ranking, and callbacks unchanged.

## 7. Edge cases

- 59-minute data hole → one session; 61 minutes → two.
- Recorded `awake` segments extend the chain (never split) and sum into `awakeMinutes`.
- Afternoon nap → separate session, `.nap`; 2 h sleep starting 1 AM → `.night`.
- InBed-only night (phone-only) → "In bed" session, no breakdown, classified via `inBedMinutes`.
- Sub-minute stage fragments: hidden as rows (existing filter) but counted in totals.
- Same night from two sources (live HealthKit + export import) with non-identical timestamps can inflate totals — pre-existing raw-row limitation (dedupKey catches exact repeats only); documented, not solved here.
- Empty input / single segment / all-point-event input → `[]` / one session / `[]` (the builder consumes only duration sleep events; point `.sleep` events stay raw Timeline rows).

## 8. Out of scope

- Persisting sessions or exposing them to the Evidence Engine (Phase 2 calls the same pure builder over its query window when it needs sleep features).
- Home's `sleepSummary` (keeps its fixed-window sum; possible later follow-up to reuse the builder).
- Hypnogram (time-ordered stage chart), per-segment drill-down, sleep trends/insights.
- Travel-aware per-segment timezone handling.

## 9. Testing

- **Package — `SleepSessionBuilderTests`:** gap-split boundaries (59/61 min), overlap chaining (awake mid-night keeps one session), totals math exact per stage, inBed excluded from asleep, nap vs night classification incl. the 1 AM crash-sleep and inBed-only cases, sub-minute inclusion, empty/single-segment inputs, deterministic ids.
- **Package — `TimelineDayBuilderTests` additions:** sleep collapses to one session item on the wake-up day (cross-midnight case), `sessionizeSleep: false` keeps raw rows, interleave ordering (session with end 07:03 sorts above a 06:50 event), severity points unaffected, non-sleep duration filter still applies.
- **App:** `TimelineViewModel` delete/undo rebuild correctness with sessions present (delete a non-sleep event on a day that also holds a session).
- **On-device checkpoint (Leo):** real ~136k-event graph — nights render as single rows on wake days, expansion breakdown sane vs. Apple Health, naps labeled, search still shows raw stages, chips read as tappable.
