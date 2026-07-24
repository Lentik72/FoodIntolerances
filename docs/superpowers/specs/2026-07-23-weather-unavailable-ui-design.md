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
| 14 | Cancellation result | **Explicit `.cancelled` case** on both backfill result enums. A cancelled fetch must not return `.fetchError(reason)`, or the emitter would stamp that reason across the whole intended range — a fabricated multi-day outage from a routine refresh-supersede. (Review P0.) |
| 15 | Location fabrication | **Trusted-coordinate provenance.** `LocationService` fabricates NYC on denied/timeout, so `resolvedCoordinate()` is non-nil and wrong-city weather is ingested and mined; the `locationDenied`/`locationUnavailable` paths never run. Provenance-tag coordinates, reject `.fabricated` for ingestion, keep it for the legacy display. **Cached is trusted only when authorized AND fresh** (persisted `cachedLocationAt` within the 5-min window) — an unbounded/denied cache would mask a real location outage. Manual always wins. (Review P0 + follow-up P1.) |
| 16 | Pressure carry is time-aware | **`(value, timestamp)`**, exposed only within `pressureReadingInterval`. A value-only carry fabricates a drop after days offline/backgrounded. All three fallback routes refactored, not just 1013. (Review P1.) |
| 17 | Healthy ≠ no-live-failure | Summary: any live failure → unavailable; else any nil success → "Not checked yet"; else the **least**-recent success. Retained failures render past-tense "Last issue — resolved" with no action; "Why it stopped" + Open Settings read `liveFailure` only. (Review P1 + notes.) |
| 18 | `insufficientData` | A 2xx forecast with < 3 usable slots is a real capability failure (today-scoped) and **marks**, rather than recreating a moon-only silent gap. Pressure stays Health-only. |

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
    case rejected             // 401/403: key invalid/revoked, or One Call not subscribed
    case locationDenied       // authorization .denied / .restricted — user-fixable
    case locationUnavailable  // authorized/.notDetermined, or only a fabricated coord
    case offline              // URLError, excluding .cancelled
    case insufficientData     // 2xx, but the response held no usable value for the day
    case badResponse          // decode failure, unexpected shape, other HTTP error
}

struct EnvironmentFailure: Codable, Equatable {
    let at: Date
    let reason: EnvironmentFailureReason
    let scopeStart: Date    // local start-of-day, inclusive
    let scopeEnd: Date      // local start-of-day, inclusive
    let timezoneID: String  // the calendar tz the scope was computed in
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
@MainActor func recordSuccess(_ capability: EnvironmentCapability, at: Date)
@MainActor func recordFailure(_ capability: EnvironmentCapability, reason: EnvironmentFailureReason,
                              scopeStart: Date, scopeEnd: Date, timezoneID: String, at: Date)
```

`recordSuccess` sets `lastSuccess` and clears `liveFailure`; it does not touch `lastFailure`. `recordFailure` sets both failure slots. **There is no cancellation path** — cancellation simply never calls either method (see §3C).

**Ownership + observation wiring.** The store is a single `@MainActor` `ObservableObject`, created once in `FoodIntolerancesApp` and shared three ways: injected into `EnvironmentalDataService` (whose `environmentalService` today comes from `LogItemViewModel`, so the app hands the same store to the emitter call and to the service), and passed as an `@EnvironmentObject` (or `@ObservedObject` on the view models) to the Timeline and Health surfaces. One instance, so a fetch that records a failure republishes to every reader; `@MainActor` because all three readers are UI and the write points are already on the main actor. The plan must thread this instance explicitly rather than letting any surface `new` its own — two stores would let the Timeline heal while Health stays stale.

**Who writes what.** The service owns the three today-scoped capabilities end to end — it knows both the reason and the scope (today…today), so it records them directly. The two backfill capabilities are split: the service knows the *reason*, but only the emitter knows the *intended range*. So `WeatherDayResult` and `AQIRangeResult` each gain **two** new cases — `.fetchError(EnvironmentFailureReason)` (replacing the bare `.fetchError`) and `.cancelled` — and the emitter records the failure with that reason plus the range it intended. `.cancelled` carries no reason and triggers a no-op abort (see §3C). This keeps scope at the only layer that knows it and avoids a record-then-overwrite dance. Both result enums changing shape is compiler-enforced across `WeatherHistoryTests` and `AirQualityIngestionTests`.

### B. Reason classification (`EnvironmentalDataService`)

Every fetch currently discards the HTTP response: `let (data, _) = try await transport.data(from: url)`. That becomes `let (data, response) = …` with a status check, so `rejected` is distinguishable from `badResponse`.

This **adds to** rather than replaces `fetchCompletedWeatherDay`'s existing error-body detection (`EnvironmentalDataService.swift:593–602`). That logic stays exactly as written — a 401 One Call body must still map to `.fetchError` and never `.absent`. Status inspection only supplies the *reason* recorded alongside it.

Classification order at each fetch site:

1. `APIConfig.…URL(…)` returned `nil` → `notConfigured` (the guard already exists; it currently just logs and returns).
2. No **trusted** coordinate (see §3B.1) → `locationDenied` if authorization is `.denied`/`.restricted`, else `locationUnavailable`.
3. HTTP status 401/403 → `rejected`.
4. Other non-2xx status → `badResponse`.
5. `URLError` (not `.cancelled`) → `offline`.
6. Success (2xx) but the aggregate is `nil` (a today forecast with < 3 usable slots) → `insufficientData` (see §3B.2).
7. `DecodingError` or unexpected shape → `badResponse`.

#### B.1 — Trusted coordinates (P0 fix)

`resolvedCoordinate()` being non-nil does **not** mean the app knows where the user is. `LocationService` fabricates New York City (`40.7128, -74.0060`) at four sites — the 5 s resolution timeout (`EnvironmentalDataService.swift:890`), the denied path (`907`), the CoreLocation error path (`1001`), and the authorization-changed path (`1030`). Today `DefaultLocationProvider.coordinate` reads `manualLocation ?? locationManager?.currentLocation` (`:96`), so a denied or timed-out user resolves to NYC, the fetch **succeeds**, and *New York's* weather is ingested and mined for a user anywhere on Earth. The `locationDenied`/`locationUnavailable` paths this feature depends on would never run.

Fix — track coordinate provenance and reject the fabricated one for graph purposes, while leaving the legacy dashboard's always-show-something behavior intact (mirrors the pressure-fallback split in §3H):

```swift
enum LocationProvenance { case device, cached, fabricated }
```

- `LocationService` publishes the provenance of `currentLocation`: `.device` when set from a real `didUpdateLocations` fix (`:960`); `.cached` when set from `lastKnownLocation` (`:884`, `:903`); `.fabricated` at the four NYC sites. The NYC assignments and `currentLocation`'s type are unchanged, so the legacy pressure/weather cards still render.
- The device fix already persists `cachedLatitude`/`cachedLongitude` (`:963–964`) with **no timestamp**. Add a persisted `cachedLocationAt` (an `@AppStorage` epoch) written at the same point, so the cache's age is knowable. Legacy display keeps reading `lastKnownLocation` regardless of age — the timestamp gates ingestion only.
- `LocationService` also exposes authorization publicly, since its `CLLocationManager` is `private`:
  ```swift
  var authorization: EnvironmentLocationAuthorization   // maps locationManager.authorizationStatus
  ```
- `DefaultLocationProvider.coordinate` returns a **trusted** coordinate only:
  ```swift
  var coordinate: CLLocationCoordinate2D? {
      if let manual = service.manualLocation { return manual }   // user-set: always trusted
      guard let loc = service.locationManager else { return nil }
      switch loc.provenance {
      case .device:     return loc.currentLocation               // a real live fix
      case .cached:     return loc.trustedCachedCoordinate       // authorized AND fresh, else nil
      case .fabricated: return nil                               // never ingest NYC
      }
  }
  ```

**Cached-coordinate policy (revised per review — bounded).** Trusting a cached fix unconditionally has two holes: the cache has no timestamp, so "recently visited" isn't guaranteed (it could be months old → wrong city); and trusting it *while authorization is denied* means turning Location off keeps ingesting cached-location weather and **never** produces `locationDenied`, directly contradicting the device gate. So `.cached` is trusted for ingestion only when **both**:

1. `authorization == .authorized`, and
2. the persisted `cachedLocationAt` is within the existing five-minute freshness window (the `300 s` already used at `:842`/`:942`; the plan lifts it to a named constant).

`LocationService.trustedCachedCoordinate` returns `lastKnownLocation` when both hold, else `nil`. Denied → cached is not trusted → the fetch reports `locationDenied` as the gate expects. Authorized but the cache is stale → `nil` → `locationUnavailable` until a fresh fix lands (then it heals). Manual still always wins; the legacy display still shows cached at any age.

This keeps the cold-launch benefit for the common case (an authorized user whose last fix is minutes old) without letting a stale or denied cache mask a real location outage.

`LocationProviding` (`HTTPTransport.swift:21`) gains the authorization property alongside `coordinate`, keeping one injectable seam so tests can drive both halves of decision 10 **and** the fabricated-coordinate rejection:

```swift
// public: it appears in the requirements of the public LocationProviding protocol,
// so it must be at least as visible as the protocol itself.
public enum EnvironmentLocationAuthorization { case denied, restricted, authorized, notDetermined }

public protocol LocationProviding {
    var coordinate: CLLocationCoordinate2D? { get }   // trusted only — nil hides a fabricated fix
    var authorization: EnvironmentLocationAuthorization { get }
}
```

`DefaultLocationProvider` maps `CLLocationManager.authorizationStatus` via `LocationService.authorization`; `.authorizedWhenInUse`/`.authorizedAlways` → `.authorized`. When the coordinate is nil purely because the only fix is fabricated while authorization is `.authorized`, the reason is `locationUnavailable` (authorized but no usable fix) — not `locationDenied`.

#### B.2 — `insufficientData`

`fetchDailyForecast` can return 2xx yet produce no aggregate: `aggregate24h` yields `nil` below three in-window slots (`EnvironmentalDataService.swift:346`), and the success branch currently just sets `forecastHigh/Low/Humidity = nil` (`:392`). That is the capability failing to produce its promised value for *today* — exactly what this UI reports — so it records `insufficientData` scoped today, and the resolver's rule 1 then marks today. This is the ONLY place `insufficientData` is raised: it is a today-forecast concern. The observed backfills keep their existing per-day `.absent` semantics (a completed day genuinely without enough hourly readings is resolved-absent, advances the watermark, and gets no marker — unchanged). `forecastAirQuality`'s thin-slot case (`meanPM25` nil) also records `insufficientData`, but that capability emits no Timeline event and is Health-only, so it surfaces only on the Health screen.

### C. Cancellation

`requestRefreshWithCooldown()` cancels the in-flight task on every refresh (`EnvironmentalDataService.swift:261`), and several fetches gate on `!Task.isCancelled`. A cancelled fetch is a **total no-op on status**: it does not record success, does not record failure, does not create or extend a scope, and does not clear a live failure.

For the three today-scoped capabilities the service enforces this directly: a single `isCancellation(_ error: Error) -> Bool` helper matching `CancellationError` and `URLError.cancelled`, checked at the top of every `catch` before any status write, plus a `Task.isCancelled` check before recording success.

For the two backfills the danger is sharper and needs an explicit signal, not a shared reason. If `fetchCompletedWeatherDay` / `fetchCompletedAirQualityRange` returned `.fetchError(reason)` on cancellation, the emitter would stamp that reason across the **whole intended range** — turning a routine refresh-supersede into a fabricated multi-day outage. So both fetches detect cancellation *first* (before the reason-classifying `catch`) and return the dedicated **`.cancelled`** case. The emitter treats `.cancelled` as: stop the pass, ingest nothing, record no failure, hold the watermark, leave any existing `liveFailure` untouched — identical to the mid-pass abort's persistence behavior but with zero status writes. `.cancelled` is distinct from `.absent` (which advances the watermark for old days) and from `.fetchError(reason)` (which records a scoped failure).

### D. Failure scope

Recorded at the point of failure from the range the caller actually intended, never reconstructed later:

| Capability | Scope |
|---|---|
| `currentPressure`, `forecastWeather`, `forecastAirQuality` | today…today |
| `observedWeather` | the pass's **intended** range, `start…yesterday`, captured before the loop |
| `observedAirQuality` | the requested `start…yesterday` |

The `observedWeather` intended range is correct even though the pass aborts mid-loop on the first `.fetchError`: an aborted pass ingests **nothing** — it `return`s ahead of `pipeline.ingest` (`EnvironmentalEventEmitter.swift:218`) — so every day in the intended range is genuinely unresolved. Recording only the days reached before the abort would under-report.

**Two success contracts, one per layer — because the two layers own different things.** The reviewer caught a contradiction in an earlier draft: today-scoped success cannot be recorded "after `pipeline.ingest`" because the service, which owns those fetches, never sees the emitter's pipeline result (today's pressure + forecast + moon + mercury are ingested together as one combined reading in the emitter at `EnvironmentalEventEmitter.swift:111`, not per-capability in the service). So the two layers define success differently, and that difference is intrinsic, not a wart:

- **Backfill capabilities (`observedWeather`, `observedAirQuality`) — persist-health, emitter-owned.** `recordSuccess` fires at exactly one point: inside the same `do` block that persists the pass and advances the watermark (`EnvironmentalEventEmitter.swift:228–235`) — after the ingest (skipped when the pass produced no events) and the watermark write both succeed — never per-day inside the loop. A pass that reached this block without a `.fetchError`/`.cancelled` abort *is* a complete pass, even if every day was resolved-`.absent` and nothing was ingested. If ingest throws, the existing `catch` holds the watermark for retry (`:233`) and must **not** record success.
- **Today capabilities (`currentPressure`, `forecastWeather`, `forecastAirQuality`) — fetch-health, service-owned.** `recordSuccess` fires in the service the moment a valid response decodes (right where each fetch publishes its `@Published` values today), independent of whether the emitter's later combined today-ingest succeeds. These three statuses mean "the fetch produced a usable value," which is exactly what the marker and Health surface report — a dead key, no location, offline, an inactive subscription. **Today's *ingestion* failure is deliberately out of this round's scope:** a local SQLite write failing is rare and already self-heals via the emitter's existing `catch` + re-emit on the next foreground (`:112–114`).

One bounded consequence to record so it doesn't read as an oversight: if today's fetch **succeeds** but the combined ingest then **fails**, `forecastWeather` has no `liveFailure` (the fetch cleared it) yet the day has no `temperature` event, so the resolver shows **no marker** and the row is briefly bare until the next foreground re-emits. That is correct for a fetch-health marker — the fetch genuinely succeeded — and the gap is transient by construction. Making the marker also cover ingestion would require the emitter to own all five capabilities and is explicitly deferred.

**Scope carries its timezone.** `EnvironmentFailure.timezoneID` is the identifier of the calendar the scope's day bounds were computed in (`calendar.timeZone.identifier`, already available at every write site). The resolver compares days using that stored timezone, so a live scoped marker stays anchored to the days it was actually about even if the device timezone changes between the failure and the render. Without it, a flight across zones could shift or drop a live marker by a day. Cheap to store, and it removes a latent correctness gap rather than documenting around it.

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

**Scope containment uses the failure's own timezone.** A day D is "inside" a scope when D's local start-of-day, computed in a calendar set to `failure.timezoneID`, lies within `[scopeStart, scopeEnd]`. The resolver's own `calendar`/`now` are used only where no scope is involved (e.g. deriving "today" for a row that has no failure to test). This makes the marker timezone-stable per §3D.

Rules, in order:

1. **Weather, today.** No `temperature` event in the day **and** `forecastWeather` has a `liveFailure` whose scope contains the day → `.weather`. (Covers both a hard forecast failure and `insufficientData`, since both are recorded against `forecastWeather` scoped today.)
2. **Weather, completed days.** No `temperature` event **and** `observedWeather` has a `liveFailure` whose scope contains the day → `.weather`.
3. **Air quality.** No `airQuality` event **and** `observedAirQuality` has a `liveFailure` whose scope contains the day → `.airQuality`. Only evaluated when rule 1/2 didn't fire, so a day missing both reports the larger story once (decision 2's "one concise message, distinguished internally"). Today never qualifies — completed-day AQI doesn't exist yet by design (`EnvironmentalEventEmitter.swift:96`).
4. Otherwise `nil`.

Consequences that fall out for free:

- A 200-day-old moon-only row is **outside** any recorded scope → no marker. The absence-≠-failure trap is handled by construction.
- A forecast temperature present with observed history failed → rule 2's "no `temperature` event" is false → no marker, forecast displays, Health explains. Decision 2 satisfied.
- A thin forecast (2xx, < 3 slots) leaves no temperature event AND records `insufficientData` on `forecastWeather` scoped today → rule 1 marks today. No moon-only silent gap.
- When the data arrives, either the event exists or the success cleared `liveFailure` — the marker vanishes with no expiry logic.

One deliberate non-rule, recorded so it doesn't read as an oversight:

- **`currentPressure` has no Timeline marker.** A day whose pressure fetch failed simply has no pressure line; inventing a marker for it would clutter rows that already show valid weather. Pressure health is visible on the Health screen, and after §3H a failed pressure fetch no longer fabricates a reading. This is decision 2 applied consistently. (Distinct from `forecastWeather` `insufficientData`, which *does* mark, because pressure isn't part of the row's weather headline while temperature is.)

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

**Summary row trailing text — three states, in this order** (so "healthy" can never mean merely "no live failure"):

1. **Any capability has a `liveFailure`** → the affected group named, e.g. `Weather history unavailable`. When more than one is failing, name the first with a `liveFailure` in this fixed order so the text is deterministic rather than dictionary-order-dependent: `currentPressure` → `forecastWeather` → `observedWeather` → `forecastAirQuality` → `observedAirQuality`. Weather leads because a dead key or denied location takes it out first and it's the larger story.
2. **Else any capability has `lastSuccess == nil`** → `Not checked yet`. On first launch every capability is nil/nil; a "most recent success" rule would print a stale-looking time or hide never-run endpoints behind one fresh one.
3. **Else** → `Updated {least-recent lastSuccess across all five}`. The **least**-recent, not the most-recent: the summary asserts "everything was known good as of this time," so one fresh endpoint must not mask an older one.

**Detail screen — per-capability row status**, each computed the same way (so a per-endpoint row never lies either): `liveFailure` present → `Unavailable`; else `lastSuccess == nil` → `Not checked yet`; else `Updated {lastSuccess}`.

```
Environment data

WEATHER
  Air pressure                    Updated 9:14 AM
  Today's forecast                Updated 9:14 AM
  Observed history                    Unavailable

AIR QUALITY
  Today's forecast                Not checked yet
  Observed history                  Updated Jul 21

WHY IT STOPPED
  Historical weather may need a valid API key or an
  active One Call subscription.  Last tried today, 8:02 AM.
```

**Bottom section — live vs resolved.** "Why it stopped" and any action read from **`liveFailure` only** — otherwise a recovered permission outage would keep telling the user to open Settings for a problem that's already fixed:

- **Any `liveFailure`** → `WHY IT STOPPED`, present tense, from the earliest-order live failure; **Open Settings** iff that reason is `locationDenied`.
- **Else any `lastFailure`** (all resolved) → `LAST ISSUE — RESOLVED`, past tense, from the most recent `lastFailure`, **no action, no Open Settings**. E.g. "Location access was off. Environment data has resumed."
- **Else** → nothing.

Reason copy:

| Reason | Live copy ("why it stopped") | Resolved copy ("last issue") | Action (live only) |
|---|---|---|---|
| `notConfigured` | "Weather data isn't configured in this build." | "Weather data wasn't configured." | — |
| `rejected` | "The weather service rejected the request." (for `observedWeather`: "Historical weather may need a valid API key or an active One Call subscription.") | "The weather service was rejecting requests." | — |
| `locationDenied` | "Location access is off, so conditions can't be looked up for where you are." | "Location access was off." | **Open Settings** (`UIApplication.openSettingsURLString`) |
| `locationUnavailable` | "Your location hasn't been determined yet." | "Your location couldn't be determined." | — |
| `offline` | "No internet connection the last time we checked." | "There was no internet connection." | — |
| `insufficientData` | "The forecast didn't include enough data for today yet." | "The forecast was briefly incomplete." | — |
| `badResponse` | "The weather service returned something unexpected." | "The weather service returned something unexpected." | — |

The `observedWeather` `rejected` copy is neutral about the cause per the review: a 401 could be an invalid or revoked key just as easily as an inactive subscription, so it names both possibilities rather than asserting the subscription is off. Open Settings appears for a live `locationDenied` only — the sole user-fixable reason (decision 10).

### H. Pressure trust separation

Three exposed concepts on `EnvironmentalDataService`, plus one private **time-stamped** carry:

- **`latestFetchedPressure: Double?`** — this refresh's genuine API result; `nil` on failure or fallback. **The emitter reads this** as `pressureHPa`, instead of `currentPressure`.
- **`lastTrustedPressure: Double?`** — the genuine observation *preceding* `latestFetchedPressure`, exposed **only when it is recent enough to compare** (see below), and the only input to the pressure-change calculation. The emitter reads it as `previousPressureHPa`. A fallback never overwrites it; neither does a cancellation.
- **`currentPressure` + display strings** — keep their fallback values purely for the legacy card. Zero legacy UI change.
- **`private var mostRecentGenuinePressure: (value: Double, at: Date)?`** — the carry that makes the shift correct across refreshes. **Time-stamped**, so a drop is only ever computed between two genuine readings taken close enough together to be a real barometric change. Never cleared at refresh start, never written by a fallback or a cancellation.

**Why time-stamped.** A value-only carry would compute a "pressure drop" between a reading today and the last genuine reading from *days ago* — after the app was offline or backgrounded — and emit a fabricated mined `pressureDrop`. So the carry stores `at`, and `lastTrustedPressure` is exposed to the emitter as non-nil **only when** `now − carry.at ≤ pressureReadingInterval` (the existing sudden-change window at `EnvironmentalDataService.swift:675`). Older than that: the delta is meaningless, so `lastTrustedPressure` reads nil and today emits pressure with no drop — the correct absence, not a fabricated one.

The carry is also load-bearing for a second reason. Without it, a success that wrote its own value into `lastTrustedPressure` would leave the emitter reading `previous == current` and **no pressure drop would ever be emitted again** — a silent regression that trades one evidence-engine defect for another. The shift is therefore:

```
refresh begins:      latestFetchedPressure = nil                        // carry untouched
success(new @ now):  prior = carry, valid iff (now − prior.at) ≤ pressureReadingInterval
                     lastTrustedPressure   = valid ? prior.value : nil  // recent genuine value only
                     mostRecentGenuinePressure = (new, now)
                     latestFetchedPressure = new
                     suddenPressureChange  = valid ? delta(prior.value → new) : false
failure / fallback:  latestFetchedPressure = nil                        // carry untouched
cancellation:        nothing written, no status recorded
```

The very first genuine reading has no prior carry, so no drop is emitted — matching today's `isFirstLoad` behavior in `updateAtmosphericPressure`.

A cooldown-rejected call (no refresh started) leaves the prior genuine value intact — correct, since re-stamping the same local day is dedup-idempotent.

**All fallback paths refactored, not just the 1013 one.** There are three contamination routes into the pressure state, and every one must stop feeding the emitter's inputs:

1. `useFallbackPressureData()` (`EnvironmentalDataService.swift:618`) — the fixed 1013 fallback.
2. `setFallbackAtmosphericPressure()` (`:686`) — routes a **cached** `lastKnownPressure` *and* a deterministic **fabricated** value through `updateAtmosphericPressure()` (`:691`, `:709`), so a test that exercised only route 1 would leave this one still poisoning the delta.
3. Any success branch that runs after a fallback.

The fix keeps all three writing the legacy display fields (`atmosphericPressure`, `currentPressure`, category) exactly as today, but **none of them touch `latestFetchedPressure` or the carry** — those are written only on a genuine API success. `updateAtmosphericPressure` (`:647`) is refactored so its sudden-change math reads the time-gated `lastTrustedPressure`, not the fallback-contaminated `currentPressure`; the legacy `suddenPressureChange` display it drives is unchanged for genuine readings and simply never fires off fabricated ones.

`EnvironmentalDataProviding` (`EnvironmentalEventEmitter.swift:8`) replaces `var currentPressure` / `var previousPressure` with `var latestFetchedPressure: Double?` / `var lastTrustedPressure: Double?`, and the emitter's reading construction (`EnvironmentalEventEmitter.swift:101`) drops the `> 0` sentinel in favor of the optionals — matching the pattern already used for temperature, where `0 °C` is a real reading and optionals are the correct absence signal (see the weather-exposures round).

## 4. Files

**New**
- `Models/EnvironmentStatus.swift` — `EnvironmentCapability`, `EnvironmentFailureReason`, `EnvironmentFailure` (with `timezoneID`), `EnvironmentCapabilityStatus`, `LocationProvenance`, `EnvironmentLocationAuthorization`.
- `Models/EnvironmentStatusStore.swift` — the `@MainActor`, observable, `UserDefaults`-backed store.
- `Views/HealthOS/Timeline/EnvironmentGapResolver.swift` — pure resolver + `EnvironmentGap`.
- `Views/HealthOS/Health/EnvironmentStatusView.swift` — the detail screen.
- `Food IntolerancesTests/EnvironmentStatusStoreTests.swift`, `EnvironmentGapResolverTests.swift`, `EnvironmentFailureClassificationTests.swift`, `PressureTrustTests.swift`, `LocationTrustTests.swift`.

**Modified**
- `EnvironmentalDataService.swift` — status writes at all five fetch sites; response status inspection; cancellation filter; `.cancelled` + `.fetchError(reason)` on both backfill results; trusted-coordinate resolution; time-stamped pressure carry + all three fallback routes; injected store.
- `HTTPTransport.swift` — `LocationProviding.coordinate` (trusted-only) + `authorization`, `EnvironmentLocationAuthorization`.
- `EnvironmentalDataService.swift` `LocationService` — `LocationProvenance`, published provenance stamped at the four NYC / cached / device-fix sites, persisted `cachedLocationAt` written with the cached lat/lon, `trustedCachedCoordinate` (authorized + fresh), public `authorization`.
- `Models/EnvironmentalEventEmitter.swift` — `EnvironmentalDataProviding` pressure optionals + store seam; `.cancelled`/`.fetchError(reason)` handling; scope recording for both backfills; `recordSuccess` only after full-pass persist; today's reading construction.
- `FoodIntolerancesApp.swift` — create the one `@MainActor EnvironmentStatusStore`, inject it into `environmentalService` and the `emitIfNeeded` call, and publish it to the Timeline + Health surfaces as an environment object.
- `LogItemViewModel.swift` — `environmentalService` construction takes the shared store (it owns the `EnvironmentalDataService` instance, `:37`/`:338`).
- `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift` — `gap` parameter, sub-line, a11y label.
- `Views/HealthOS/Timeline/TimelineView.swift` / `TimelineViewModel.swift` — read the store, resolve and pass `gap`.
- `Views/HealthOS/Health/HealthTabView.swift` — "Data sources" card + summary row; reads the store.
- **Previews** that construct these views (`EnvironmentSummaryRow`, `HealthTabView`, `TimelineView`, and the new `EnvironmentStatusView`) get a preview-only in-memory store instance so they compile without the app-level injection.
- `Food IntolerancesTests/EnvironmentalEmitterTests.swift`, `EnvironmentalDataServiceDITests.swift`, `WeatherHistoryTests.swift`, `AirQualityIngestionTests.swift` — stub conformance updates (the protocol + result-enum changes are compiler-enforced) and scope/cancellation assertions.

## 5. Testing

**Pressure (Leo's required four, plus one)**
- A fallback emits **no** `pressure` and no `pressureDrop` event.
- A genuine 1006 reading after a 1013 fallback does **not** fabricate a 7 hPa drop.
- Two genuine readings crossing the threshold still emit the real drop.
- **Three** consecutive genuine readings still emit a drop on the third — the carry regression guard. A `lastTrustedPressure` that wrote its own value would pass the two-reading test and fail here, silently killing every subsequent drop.
- **Two genuine readings more than `pressureReadingInterval` apart emit no drop** — the time-gate. A value-only carry would fabricate one.
- **The `setFallbackAtmosphericPressure` route** (cached and fabricated) emits no pressure/`pressureDrop` event and does not contaminate the next genuine delta — the second contamination path, tested independently of route 1.
- The legacy fallback display (`atmosphericPressure`, `atmosphericPressureCategory`, `currentPressure`) is unchanged for both fallback routes.
- A cancelled refresh emits no pressure event and leaves the carry untouched.
- The first genuine reading emits pressure but no drop (no prior carry).

**Location trust (P0 + cached bound)**
- Fabricated (NYC) provenance → `coordinate` reads nil → the fetch records `locationDenied`/`locationUnavailable` (per authorization) and ingests **no** weather — not New York's.
- `.device` provenance → `coordinate` non-nil → normal fetch.
- `.cached` + authorized + `cachedLocationAt` within the freshness window → trusted → normal fetch.
- `.cached` + authorized + **stale** `cachedLocationAt` → nil → `locationUnavailable` (not wrong-city).
- `.cached` + **denied** (even if fresh) → nil → `locationDenied` (turning Location off stops ingestion; the cache can't mask it).
- A manual `setLocation` coordinate wins even when `LocationService` provenance is `.fabricated` or the cache is stale/denied.
- Authorization `.denied` + fabricated coord → `locationDenied`; `.authorized` + fabricated coord → `locationUnavailable` (authorized but no usable fix).

**Resolver**
- Inside a live scope + missing reading → marker.
- Inside a live scope + reading present → none.
- **Outside every scope + missing reading → none** (the 200-day-old moon-only row).
- Forecast temperature present + `observedWeather` failed → none.
- Missing both weather and AQI → `.weather` only (one concise message).
- Today with `observedAirQuality` failing → no AQI marker (today has no completed-day AQI by design).
- Thin forecast (`insufficientData` on `forecastWeather`, no temperature event) → today marked `.weather`.
- A day with no pressure and only `currentPressure` failing → no marker (pressure is Health-only).
- Scope `[D1…D2]` recorded in one timezone still contains/excludes the right days after the resolver's calendar is switched to a different zone (timezone-anchored containment).

**Health summary + detail states**
- All nil/nil (first launch) → summary `Not checked yet`.
- All succeeded at different times, no live failure → summary shows the **least**-recent success (not the most-recent).
- Two capabilities failing simultaneously names the earlier one in the declared order, deterministically across runs.
- A per-capability row: live failure → `Unavailable`; nil success → `Not checked yet`; else `Updated …`.
- A capability with a cleared `liveFailure` but a retained `lastFailure` → bottom section reads `LAST ISSUE — RESOLVED`, past tense, and shows **no** Open Settings even when the resolved reason was `locationDenied`.
- A live `locationDenied` → Open Settings present.

**Store + success contracts**
- `recordSuccess` clears `liveFailure` and retains `lastFailure`.
- Backfill success is recorded only after a full pass persists — an ingest that throws records no success (state unchanged).
- A today capability records success when its fetch response decodes, **independent** of whether the emitter's later combined today-ingest succeeds (fetch-health contract). A today fetch that succeeds while ingest later fails still clears that capability's `liveFailure`.
- Cancellation writes nothing and clears nothing (a cancelled fetch between a failure and a read leaves the failure live).
- Round-trips through `UserDefaults`, including `timezoneID` (a relaunch keeps the marker anchored).

**Classification**
- 401 → `rejected`; other non-2xx → `badResponse`.
- `URLError.notConnectedToInternet` → `offline`.
- `URLError.cancelled` and `CancellationError` → no write at all; the two backfills return `.cancelled`, not `.fetchError`.
- No trusted coordinate under `.denied` → `locationDenied`; under `.notDetermined`/`.authorized` → `locationUnavailable`.
- `nil` URL (no API key) → `notConfigured`.
- 2xx forecast with < 3 usable slots → `insufficientData` scoped today.
- A One Call 401 error body still returns `.fetchError(reason:)` (never `.absent`) **and** records `rejected` — the existing distinction is preserved, not replaced.

**Scope**
- A `day_summary` pass aborting on day 3 of 30 records `start…yesterday`, not `start…day3`.
- A `day_summary` pass **cancelled** on day 3 records **nothing** (no scope, watermark held).
- An AQI range failure records the requested range.
- A forecast failure records today…today only, stamped with the current calendar's `timezoneID`.

**App suites** run with `-parallel-testing-enabled NO`; the lone `** TEST FAILED **` from the known `SwiftDataMigratorTests` teardown crash is expected. Core suites should be unaffected — no core files change.

**Device pass**
- Turn location off → Environment rows show the muted marker, Health reads `locationDenied` with a working Open Settings button, and **no New York weather and no fabricated pressure are ingested** for those days (verify via the debug event view — the P0 that motivated this round).
- Restore location → one successful pass clears every marker together and the Health screen flips to `Updated`, while the bottom section now reads `LAST ISSUE — RESOLVED` with **no** Open Settings button.
- Confirm a forecast-present/observed-failed day keeps showing its forecast with no marker.
- Confirm the legacy app's pressure card is visually identical to before, on both fallback routes.

## 6. Out of scope

- Any Home-tab banner or notification (decision 1).
- Manual location entry. `setLocation(latitude:longitude:)` and the dead `showZipCodePrompt` flag (`EnvironmentalDataService.swift:62`) exist but have no HealthOS UI; adding one is expansion, and this round is hardening. `locationDenied`'s only action is Open Settings.
- Launch double-emit cleanup (queue #2), demo-data hygiene (#3), proactive poor-air warnings (#4).
- Any change to mining, exposure sources, or the observed-wins precedence.
- Retiring the legacy 1013 pressure fallback from the legacy card (decision 12 keeps it).
- A full failure log or history list — Health retains the single most recent failure per capability, not a timeline of them.
