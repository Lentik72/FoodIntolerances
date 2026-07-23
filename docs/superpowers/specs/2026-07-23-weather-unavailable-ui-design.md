# Weather-Unavailable UI State — Design

**Date:** 2026-07-23
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Make failed environment fetches visible instead of silent. Record per-capability fetch health (last success, live failure with its attempted day-scope, retained failure history), surface a muted per-day marker on the Timeline Environment row, add a Health-tab status row plus detail screen with the plain-language reason and a fix action when the user can act. Folds in a data-integrity prerequisite: stop the pressure fallback fabricating readings and poisoning pressure-drop deltas.

Follow-up #1 of the four queued after the observed-weather-mining round ("harden before expanding").

**Not touched:** `HealthGraphCore` (no core changes anywhere in this round). The evidence engine, exposure sources, ingestion provenance/dedup, watermark policy, the observed-wins display precedence, the legacy food-intolerance app's pressure card, and the Home tab. No new user-facing alerts or banners.

---

## 1. Problem

When environment data can't be fetched, the app looks fine. During the Jul 22–23 device gate the API key was dead for hours: Timeline still drew an `Environment` row for every day, still expandable, reading `Waxing Gibbous`. Nothing anywhere said that day's temperature, humidity, and air quality were simply missing. It took git archaeology to find out why. The Insights weather cards just quietly had fewer days of data.

Four causes produce that, and they are not equally fixable:

| Cause | What breaks | Who can fix it |
|---|---|---|
| No API key in the build (the Dec-2025 audit hole) | everything weather — `APIConfig.isWeatherAvailable` is already `false` | Leo, in the build config |
| Key rejected / One Call 3.0 not subscribed | 401s — forecast may keep working while observed backfill dies | Leo, at OpenWeather |
| No location (denied, or unresolved) | everything — every fetch bails at `resolvedCoordinate()` | **the user**, in Settings (denied only) |
| Network down / provider hiccup | everything, temporarily | fixes itself |

Two structural traps shape the design:

**Absence ≠ failure.** A day from six months ago legitimately has moon phase only — `backfillDerived` reaches 365 days but the weather backfill caps at 30. Failure cannot be inferred from missing readings; the app has to record that it tried and failed, and over which days.

**In two of the four cases it isn't silence, it's fabrication.** `fetchAtmosphericPressure()` catches any failure and calls `useFallbackPressureData()` (`EnvironmentalDataService.swift:618`), which sets `currentPressure = 1013.0`, `previousPressure = 1013.0`, category `"Normal"`. The emitter reads `service.currentPressure > 0` (`EnvironmentalEventEmitter.swift:101`) and writes a real 1013 hPa `pressure` event into the graph. Worse, the next *successful* fetch runs `previousPressure = currentPressure` in `updateAtmosphericPressure` (`EnvironmentalDataService.swift:667`) against the fake 1013 — a true 1006 reading then looks like a 7 hPa fall, past the 6 hPa threshold, emitting a `pressureDrop` that never happened. `pressureDrop` is a mined exposure (`DerivedEventExposureSources.swift:23`), so fabricated drops reach symptom-association mining.

The dead-key case dodges this specifically because `weatherURL()` returns `nil` and the nil-URL guard returns *before* the fallback — which is why Jul 22 showed moon-only rows rather than fake pressure. Location-denied and network-failure do not dodge it. Under the marker design below, a location-denied day would otherwise render `1013 hPa` directly above `Weather unavailable`.

## 2. Decisions (Leo, 2026-07-23)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Placement | **Timeline row + Health tab.** Timeline shows the consequence where missing data matters; Health is the durable diagnostic (last success, affected signals, reason, action only when fixable). **No Home banner** — a passive environment feature shouldn't become an interrupting alert, least of all for provider/subscription failures the user cannot repair. |
| 2 | Partial failure | **Never replace valid data with the warning.** Forecast temperature present but observed history failed → keep showing the forecast, no Timeline marker; Health explains that observed updates are unavailable. |
| 3 | Trigger | **Immediately, self-healing.** The marker appears only after an actual failed attempt (never merely because data is absent) and disappears on its own when the data arrives. No timers, no expiry, no grace period — the grace period is exactly what let the dead key hide. Rejected: completed-days-only (a day late) and sustained-failure thresholds (a state machine that buys quiet with delay). |
| 4 | Tone | **Status, not warning.** Muted caption, no color, no icon, no alarming language. |
| 5 | Cancellation | **Excluded entirely.** Normal refresh cancellation must never create, extend, or clear a failure — `requestRefreshWithCooldown()` cancels the in-flight task on every refresh. |
| 6 | Row layout | **Muted sub-line under the headline.** The valid summary stays on top unchanged; the marker sits beneath in caption/muted. Visible without tapping. Rejected: taking the headline slot (displaces the moon) and inline append (wraps anyway, reads as one run-on fact). |
| 7 | Health surface | **Always-visible summary row → detail screen.** Always present, so "data is flowing" is confirmable rather than inferred from the absence of a warning. Rejected: only-when-broken (absence of warning and absence of feature look identical — the failure mode this round exists to fix). |
| 8 | Status granularity | **Per capability, not per UI group.** `/weather` and `/forecast` fail independently; a successful pressure fetch must not hide a failed temperature forecast. Same for AQI forecast vs history. |
| 9 | Health screen grouping | **All five capabilities listed** under two plain headers. Decision 8's logic doesn't stop at the store — an aggregated "Conditions & forecast — Updated 9:14 AM" row hides a dead forecast just as effectively. |
| 10 | Location semantics | **Split.** `resolvedCoordinate() == nil` doesn't imply denial — location may still be resolving. `locationDenied` (authorization `.denied`/`.restricted`) gets Open Settings; `locationUnavailable` does not. |
| 11 | Failure scope | **Persisted with the failure, not inferred.** A global last-failure plus watermarks cannot prove every unresolved day was attempted. Each failure records the day range it blocked. Watermarks remain useful for reach but must not manufacture per-day failure state. |
| 12 | Pressure fabrication | **Fix the data path in this round** — a data-integrity prerequisite for an honest unavailable state. Separate `latestFetchedPressure` (emitter input) from `lastTrustedPressure` (delta input); the legacy display keeps its 1013 fallback unchanged. Rejected: dropping the fallback everywhere (changes legacy UI outside this round's remit) and deferring (ships a Timeline that can show fabricated pressure above "Weather unavailable"). |
| 13 | First-run volume | **Accepted.** A fresh install with location off marks all 30 in-reach days at once. Every one was explicitly inside a blocked backfill pass, the marker is muted, and they self-heal together in one successful pass. |

## 3. Architecture

All new code is app-layer. `HealthGraphCore` is untouched.

### A. `EnvironmentStatusStore` (new, app layer)

Five capabilities — one per fetch that can fail on its own:

| Capability | Endpoint | Feeds |
|---|---|---|
| `currentPressure` | 2.5 `/weather` | pressure, pressure drop |
| `forecastWeather` | 2.5 `/forecast` | today's temperature/humidity |
| `forecastAirQuality` | 2.5 `/air_pollution` | today's AQI (kept for the future warnings round) |
| `observedAirQuality` | 2.5 `/air_pollution/history` | completed-day AQI |
| `observedWeather` | 3.0 `/onecall/day_summary` | completed-day temperature/humidity |

Moon phase and Mercury retrograde are computed locally and never fail, so they have no capability.

```swift
enum EnvironmentCapability: String, CaseIterable, Codable {
    case currentPressure, forecastWeather, forecastAirQuality
    case observedAirQuality, observedWeather
}

enum EnvironmentFailureReason: String, Codable {
    case notConfigured        // no API key in the build
    case rejected             // 401/403: key invalid, or One Call 3.0 not subscribed
    case locationDenied       // authorization .denied / .restricted — user-fixable
    case locationUnavailable  // authorized or .notDetermined, but no fix yet
    case offline              // URLError, excluding .cancelled
    case badResponse          // decode failure, unexpected shape, other HTTP error
}

struct EnvironmentFailure: Codable, Equatable {
    let at: Date
    let reason: EnvironmentFailureReason
    let scopeStart: Date   // local start-of-day, inclusive
    let scopeEnd: Date     // local start-of-day, inclusive
}

struct EnvironmentCapabilityStatus: Codable, Equatable {
    var lastSuccess: Date?
    var liveFailure: EnvironmentFailure?   // cleared by the next success — drives Timeline
    var lastFailure: EnvironmentFailure?   // never cleared by success — drives Health's "why"
}
```

Two failure slots make decision 3 structural rather than procedural: `liveFailure` is current completeness, so the Timeline heals by itself; `lastFailure` is history, so Health can still explain what happened after the Timeline is clean.

`EnvironmentStatusStore` is an `ObservableObject` holding `[EnvironmentCapability: EnvironmentCapabilityStatus]`, persisted to `UserDefaults` as JSON under `hg.env.status`. **Persisted, not in-memory:** the backfill retry throttle is one hour, so an in-memory store would blank the marker for up to an hour after every launch — the silent-gap failure mode again.

Its write API is deliberately narrow:

```swift
func recordSuccess(_ capability: EnvironmentCapability, at: Date)
func recordFailure(_ capability: EnvironmentCapability, reason: EnvironmentFailureReason,
                   scopeStart: Date, scopeEnd: Date, at: Date)
```

`recordSuccess` sets `lastSuccess` and clears `liveFailure`; it does not touch `lastFailure`. `recordFailure` sets both failure slots. **There is no cancellation path** — cancellation simply never calls either method (see §3C).

The store is injected into `EnvironmentalDataService` (defaulting to a shared instance) and read by both view surfaces, matching how the service is already wired as an `ObservableObject`.

**Who writes what.** The service owns the three today-scoped capabilities end to end — it knows both the reason and the scope (today…today), so it records them directly. The two backfill capabilities are split: the service knows the *reason*, but only the emitter knows the *intended range*. So `WeatherDayResult.fetchError` and `AQIRangeResult.fetchError` gain an associated `EnvironmentFailureReason`, and the emitter records the failure with that reason plus the range it intended. This keeps scope at the only layer that actually knows it and avoids a record-then-overwrite dance. Both result enums changing shape is compiler-enforced across `WeatherHistoryTests` and `AirQualityIngestionTests`.

### B. Reason classification (`EnvironmentalDataService`)

Every fetch currently discards the HTTP response: `let (data, _) = try await transport.data(from: url)`. That becomes `let (data, response) = …` with a status check, so `rejected` is distinguishable from `badResponse`.

This **adds to** rather than replaces `fetchCompletedWeatherDay`'s existing error-body detection (`EnvironmentalDataService.swift:593–602`). That logic stays exactly as written — a 401 One Call body must still map to `.fetchError` and never `.absent`. Status inspection only supplies the *reason* recorded alongside it.

Classification order at each fetch site:

1. `APIConfig.…URL(…)` returned `nil` → `notConfigured` (the guard already exists; it currently just logs and returns).
2. `resolvedCoordinate() == nil` → `locationDenied` if authorization is `.denied`/`.restricted`, else `locationUnavailable`.
3. HTTP status 401/403 → `rejected`.
4. Other non-2xx status → `badResponse`.
5. `URLError` (not `.cancelled`) → `offline`.
6. `DecodingError` or unexpected shape → `badResponse`.

`LocationProviding` (`HTTPTransport.swift:21`) gains an authorization property alongside `coordinate`, keeping one injectable seam so tests can drive both halves of decision 10:

```swift
enum EnvironmentLocationAuthorization { case denied, restricted, authorized, notDetermined }

public protocol LocationProviding {
    var coordinate: CLLocationCoordinate2D? { get }
    var authorization: EnvironmentLocationAuthorization { get }
}
```

`DefaultLocationProvider` (`EnvironmentalDataService.swift:92`) maps `CLLocationManager.authorizationStatus`; `.authorizedWhenInUse`/`.authorizedAlways` → `.authorized`.

### C. Cancellation

`requestRefreshWithCooldown()` cancels the in-flight task on every refresh (`EnvironmentalDataService.swift:261`), and several fetches gate on `!Task.isCancelled`. A cancelled fetch is a **total no-op on status**: it does not record success, does not record failure, does not create or extend a scope, and does not clear a live failure.

Implementation: a single `isCancellation(_ error: Error) -> Bool` helper matching `CancellationError` and `URLError.cancelled`, checked at the top of every `catch` before any status write, plus a `Task.isCancelled` check before recording success.

### D. Failure scope

Recorded at the point of failure from the range the caller actually intended, never reconstructed later:

| Capability | Scope |
|---|---|
| `currentPressure`, `forecastWeather`, `forecastAirQuality` | today…today |
| `observedWeather` | the pass's **intended** range, `start…yesterday`, captured before the loop |
| `observedAirQuality` | the requested `start…yesterday` |

The `observedWeather` intended range is correct even though the pass aborts mid-loop on the first `.fetchError`: an aborted pass ingests **nothing** — it `return`s ahead of `pipeline.ingest` (`EnvironmentalEventEmitter.swift:218`) — so every day in the intended range is genuinely unresolved. Recording only the days reached before the abort would under-report.

Because scope lives on the failure, the emitter must be able to write status. It receives the store through the same `EnvironmentalDataProviding` seam pattern already used for everything else, so `EnvironmentalEmitterTests` can assert scope with a stub.

### E. `EnvironmentGapResolver` (new, app layer, pure)

A plain type over (status snapshot, the day's own events + `dayStart`) — no SwiftUI, no I/O, unit-testable directly.

```swift
enum EnvironmentGap { case weather, airQuality }

static func gap(for summary: EnvironmentDaySummary,
                status: [EnvironmentCapability: EnvironmentCapabilityStatus],
                now: Date, calendar: Calendar) -> EnvironmentGap?
```

**No watermark inputs.** Once a failure carries its own scope, the scope *is* the reach: days beyond the 30-day cap were never attempted, so they appear in no scope and need no separate cap test. Passing watermarks in would be a second, redundant source of truth for the same question — exactly the coupling decision 11 removes. The resolver therefore needs no `UserDefaults` access at all.

Rules, in order:

1. **Weather, today.** No `temperature` event in the day **and** `forecastWeather` has a `liveFailure` whose scope contains today → `.weather`.
2. **Weather, completed days.** No `temperature` event **and** `observedWeather` has a `liveFailure` whose scope contains the day → `.weather`.
3. **Air quality.** No `airQuality` event **and** `observedAirQuality` has a `liveFailure` whose scope contains the day → `.airQuality`. Only evaluated when rule 1/2 didn't fire, so a day missing both reports the larger story once (decision 2's "one concise message, distinguished internally"). Today never qualifies — completed-day AQI doesn't exist yet by design (`EnvironmentalEventEmitter.swift:96`).
4. Otherwise `nil`.

Consequences that fall out for free:

- A 200-day-old moon-only row is **outside** any recorded scope → no marker. The absence-≠-failure trap is handled by construction.
- A forecast temperature present with observed history failed → rule 2's "no `temperature` event" is false → no marker, forecast displays, Health explains. Decision 2 satisfied.
- When the data arrives, either the event exists or the success cleared `liveFailure` — the marker vanishes with no expiry logic.

Two deliberate non-rules, recorded so they don't read as oversights:

- **`currentPressure` has no Timeline marker.** A day whose pressure fetch failed simply has no pressure line; inventing a marker for it would clutter rows that already show valid weather. Pressure health is visible on the Health screen, and after §3H a failed pressure fetch at least no longer fabricates a reading. This is decision 2 applied consistently.
- **A successful fetch that yields no usable value produces no marker.** `aggregate24h` returns `nil` below three in-window slots, so the day gets no temperature event even though the fetch succeeded. Per decision 3 the marker requires an *actual failed attempt*, so this stays unmarked. Treating thin-but-valid responses as failures is a judgment call about provider data quality, not fetch health, and belongs to a different round.

### F. Timeline row

`EnvironmentSummaryRow` gains a `gap: EnvironmentGap?` parameter, supplied at the `TimelineView` call site (`TimelineView.swift:162`) from the resolver. The trailing slot becomes a `VStack(alignment: .trailing)`: the existing headline (`AQIValueLabel` / `MoonPhaseLabel` / plain `Text`) unchanged on top, and when `gap != nil` a second line beneath in `.caption` / `HealthTheme.inkMuted` — no color, no icon, per decision 4.

Copy: `Weather unavailable` · `Air quality unavailable`.

The accessibility label extends from `"Environment, \(headline)"` to `"Environment, \(headline), weather unavailable"`. Expandability is unchanged — the marker never makes a row expandable or inexpandable.

```
COLLAPSED — key dead, day has moon phase only

  ▎  ☁  Environment           Waxing Gibbous  ›
                          Weather unavailable

COLLAPSED — pressure survived, weather didn't

  ▎  ☁  Environment                1014 hPa  ›
                          Weather unavailable

COLLAPSED — forecast present, only observed failed (no marker)

  ▎  ☁  Environment            18–26°C · 64%  ›
```

### G. Health tab

A new "Data sources" card in `HealthTabView`, above the existing Safety/Temperature/Units card, with one summary row → `EnvironmentStatusView`.

Summary row trailing text: all healthy → `Updated 9:14 AM` (most recent success across capabilities); anything failing → the affected group named, e.g. `Weather history unavailable`, so the summary points at something real before you tap.

When more than one capability is failing the summary names the first with a `liveFailure` in this fixed order, so the text is deterministic rather than dictionary-order-dependent: `currentPressure` → `forecastWeather` → `observedWeather` → `forecastAirQuality` → `observedAirQuality`. Weather leads because a dead key or denied location takes it out first and it is the larger story; the detail screen shows every failure regardless.

Detail screen — all five capabilities under two plain headers (decision 9):

```
Environment data

WEATHER
  Air pressure                    Updated 9:14 AM
  Today's forecast                Updated 9:14 AM
  Observed history                    Unavailable

AIR QUALITY
  Today's forecast                Updated 9:14 AM
  Observed history                  Updated Jul 21

WHY IT STOPPED
  Historical weather needs a separate subscription
  that isn't active.  Last tried Jul 23 at 8:02 AM.
```

"Why it stopped" reads from `lastFailure` (retained), so it still explains a resolved outage after the Timeline has healed. Reason copy:

| Reason | Copy | Action |
|---|---|---|
| `notConfigured` | "Weather data isn't configured in this build." | — |
| `rejected` | "The weather service rejected the request." (for `observedWeather`: "Historical weather needs a separate subscription that isn't active.") | — |
| `locationDenied` | "Location access is off, so conditions can't be looked up for where you are." | **Open Settings** (`UIApplication.openSettingsURLString`) |
| `locationUnavailable` | "Your location hasn't been determined yet." | — |
| `offline` | "No internet connection the last time we checked." | — |
| `badResponse` | "The weather service returned something unexpected." | — |

Open Settings appears for `locationDenied` only — the sole user-fixable reason (decision 10).

### H. Pressure trust separation

Three exposed concepts on `EnvironmentalDataService`, plus one private carry:

- **`latestFetchedPressure: Double?`** — this refresh's genuine API result; `nil` on failure or fallback. **The emitter reads this** as `pressureHPa`, instead of `currentPressure`.
- **`lastTrustedPressure: Double?`** — the genuine observation *preceding* `latestFetchedPressure`, and the only input to the pressure-change calculation. The emitter reads it as `previousPressureHPa`. A fallback never overwrites it; neither does a cancellation.
- **`currentPressure` + display strings** — keep their fallback values purely for the legacy card. Zero legacy UI change.
- **`private var mostRecentGenuinePressure: Double?`** — the carry that makes the shift correct across refreshes. Never cleared at refresh start, never written by a fallback or a cancellation.

The carry is load-bearing, not incidental. Without it, a success that wrote its own value into `lastTrustedPressure` would leave the emitter reading `previous == current` and **no pressure drop would ever be emitted again** — a silent regression that trades one evidence-engine defect for another. The shift is therefore:

```
refresh begins:      latestFetchedPressure = nil          // lastTrusted, carry untouched
success(new):        lastTrustedPressure   = mostRecentGenuinePressure   // the prior genuine value
                     mostRecentGenuinePressure = new
                     latestFetchedPressure = new
                     suddenPressureChange  = delta(lastTrustedPressure → new)
failure / fallback:  latestFetchedPressure = nil          // lastTrusted, carry untouched
cancellation:        nothing written, no status recorded
```

The very first genuine reading leaves `lastTrustedPressure` nil, so no drop is emitted — matching today's `isFirstLoad` behavior in `updateAtmosphericPressure`.

A cooldown-rejected call (no refresh started) leaves the prior genuine value intact — correct, since re-stamping the same local day is dedup-idempotent.

`EnvironmentalDataProviding` (`EnvironmentalEventEmitter.swift:8`) replaces `var currentPressure` / `var previousPressure` with `var latestFetchedPressure: Double?` / `var lastTrustedPressure: Double?`, and the emitter's reading construction (`EnvironmentalEventEmitter.swift:101`) drops the `> 0` sentinel in favor of the optionals — matching the pattern already used for temperature, where `0 °C` is a real reading and optionals are the correct absence signal (see the weather-exposures round).

`updateAtmosphericPressure` (`EnvironmentalDataService.swift:647`) computes `suddenPressureChange` and the emitted delta against `lastTrustedPressure` rather than the fallback-contaminated `currentPressure`.

## 4. Files

**New**
- `Models/EnvironmentStatus.swift` — `EnvironmentCapability`, `EnvironmentFailureReason`, `EnvironmentFailure`, `EnvironmentCapabilityStatus`.
- `Models/EnvironmentStatusStore.swift` — the observable, `UserDefaults`-backed store.
- `Views/HealthOS/Timeline/EnvironmentGapResolver.swift` — pure resolver + `EnvironmentGap`.
- `Views/HealthOS/Health/EnvironmentStatusView.swift` — the detail screen.
- `Food IntolerancesTests/EnvironmentStatusStoreTests.swift`, `EnvironmentGapResolverTests.swift`, `EnvironmentFailureClassificationTests.swift`, `PressureTrustTests.swift`.

**Modified**
- `EnvironmentalDataService.swift` — status writes at all five fetch sites; response status inspection; cancellation filter; `latestFetchedPressure` / `lastTrustedPressure`; `DefaultLocationProvider` authorization.
- `HTTPTransport.swift` — `LocationProviding.authorization`, `EnvironmentLocationAuthorization`.
- `Models/EnvironmentalEventEmitter.swift` — `EnvironmentalDataProviding` pressure optionals; scope recording for both backfills; today's reading construction.
- `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift` — `gap` parameter, sub-line, a11y label.
- `Views/HealthOS/Timeline/TimelineView.swift` — resolve and pass `gap`.
- `Views/HealthOS/Health/HealthTabView.swift` — "Data sources" card + summary row.
- `Food IntolerancesTests/EnvironmentalEmitterTests.swift`, `EnvironmentalDataServiceDITests.swift`, `WeatherHistoryTests.swift`, `AirQualityIngestionTests.swift` — stub conformance updates (the protocol change is compiler-enforced) and scope assertions.

## 5. Testing

**Pressure (Leo's required four, plus one)**
- A fallback emits **no** `pressure` and no `pressureDrop` event.
- A genuine 1006 reading after a 1013 fallback does **not** fabricate a 7 hPa drop.
- Two genuine readings crossing the threshold still emit the real drop.
- **Three** consecutive genuine readings still emit a drop on the third — the carry regression guard. A `lastTrustedPressure` that wrote its own value would pass the two-reading test and fail here, silently killing every subsequent drop.
- The legacy fallback display (`atmosphericPressure`, `atmosphericPressureCategory`, `currentPressure`) is unchanged.
- A cancelled refresh emits no pressure event and leaves `lastTrustedPressure` untouched.
- The first genuine reading emits pressure but no drop (`lastTrustedPressure` nil).

**Resolver**
- Inside a live scope + missing reading → marker.
- Inside a live scope + reading present → none.
- **Outside every scope + missing reading → none** (the 200-day-old moon-only row).
- Forecast temperature present + `observedWeather` failed → none.
- Missing both weather and AQI → `.weather` only (one concise message).
- Today with `observedAirQuality` failing → no AQI marker (today has no completed-day AQI by design).
- A day with no temperature after a *successful* forecast fetch that yielded no usable aggregate → no marker.
- A day with no pressure and `currentPressure` failing → no marker (pressure is Health-only).

**Health summary**
- Two capabilities failing simultaneously names the earlier one in the declared order, deterministically across runs.

**Store**
- `recordSuccess` clears `liveFailure` and retains `lastFailure`.
- Cancellation writes nothing and clears nothing (a cancelled fetch between a failure and a read leaves the failure live).
- Round-trips through `UserDefaults` (a relaunch keeps the marker).

**Classification**
- 401 → `rejected`; other non-2xx → `badResponse`.
- `URLError.notConnectedToInternet` → `offline`.
- `URLError.cancelled` and `CancellationError` → no write at all.
- `nil` coordinate under `.denied` → `locationDenied`; under `.notDetermined` → `locationUnavailable`.
- `nil` URL (no API key) → `notConfigured`.
- A One Call 401 error body still returns `.fetchError` (never `.absent`) **and** records `rejected` — the existing behavior is preserved, not replaced.

**Scope**
- A `day_summary` pass aborting on day 3 of 30 records `start…yesterday`, not `start…day3`.
- An AQI range failure records the requested range.
- A forecast failure records today…today only.

**App suites** run with `-parallel-testing-enabled NO`; the lone `** TEST FAILED **` from the known `SwiftDataMigratorTests` teardown crash is expected. Core suites should be unaffected — no core files change.

**Device pass**
- Turn location off → Environment rows show the muted marker, Health reads `locationDenied` with a working Open Settings button, no fabricated pressure appears in any row.
- Restore location → one successful pass clears every marker together and the Health screen flips to `Updated`, while "Why it stopped" still shows the resolved outage.
- Confirm a forecast-present/observed-failed day keeps showing its forecast with no marker.
- Confirm the legacy app's pressure card is visually identical to before.

## 6. Out of scope

- Any Home-tab banner or notification (decision 1).
- Manual location entry. `setLocation(latitude:longitude:)` and the dead `showZipCodePrompt` flag (`EnvironmentalDataService.swift:62`) exist but have no HealthOS UI; adding one is expansion, and this round is hardening. `locationDenied`'s only action is Open Settings.
- Launch double-emit cleanup (queue #2), demo-data hygiene (#3), proactive poor-air warnings (#4).
- Any change to mining, exposure sources, or the observed-wins precedence.
- Retiring the legacy 1013 pressure fallback from the legacy card (decision 12 keeps it).
- A full failure log or history list — Health retains the single most recent failure per capability, not a timeline of them.
