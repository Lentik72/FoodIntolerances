# What Lifts Your Mood Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a good-mood outcome so the engine mines *what lifts your mood* (not just what lowers it), un-suppress mood edges from the Insights feed, and give mood insights warm, tentative, directional phrasing — both directions, positive-led.

**Architecture:** Additive engine change — a new `OutcomeKey.goodMood` (a mood event `≥ goodMoodThreshold`), wired through the outcome miner and the edge-identity layer, then surfaced with mood-specific phrasing. No change to the engine's gate structure. Mines against the exposures already wired (incl. barometric pressure). Moon/mercury/weather exposures + plausibility tiering are the NEXT round, not here.

**Tech Stack:** Swift, Swift Testing (`import Testing`, `@Test`, `#expect`), GRDB. Package logic via `swift test`; the one app-layer wiring via `xcodebuild ... -parallel-testing-enabled NO`.

Design: `docs/superpowers/specs/2026-07-19-what-lifts-your-mood-design.md`.

## Global Constraints

- **`goodMoodThreshold = 3`; `lowMoodThreshold` stays `1`.** On the 1–3 mood scale: Rough(1) → `.lowMood`, Okay(2) → **no** outcome, Good(3) → `.goodMood`. A mood event maps to **at most one** outcome. (spec §2, §3A)
- **`OutcomeKey.goodMood` is additive** — `symptom(String)` and `lowMood` are unchanged; every `switch` over `OutcomeKey` must stay exhaustive.
- **Edge identity mirrors `lowMood`:** `goodMood` ↔ token `"mood:good"` ↔ columns `("mood","good")`. (`lowMood` stays `"mood:low"`/`("mood","low")`.) (spec §3B)
- **Un-suppress mood edges** — delete the `toCategory != "mood"` filter added last round; both low- and good-mood edges surface. (spec §3C)
- **No causal language** in phrasing — "seems to", "is linked to", never "causes"/bare "lifts". The `InsightPhrasing` "NO causal language" rule and its `noCausalLanguage` test bind here. (spec §2, §7)
- **Positive-led via framing, not a re-sort** — the feed keeps its existing confidence/status ordering. (spec §5)
- **Out of scope:** new exposures (moon/mercury/weather), the plausibility-tier presentation, any capture/crisis/gate change. One-offs need NO handling (the recurrence + stability gates already exclude them). (spec §4, §8)
- **App-target tests MUST run with `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash.
- **Simulator:** iPhone 17 Pro (iOS 26.5).

---

### Task 1: Core — the good-mood outcome + edge identity

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` (`OutcomeKey`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (add `goodMoodThreshold`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/OutcomeSource.swift` (`.mood` case)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift` (`toToken`, `columns`, `parseTo`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift` (`OutcomeSourceTests`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EdgeIdentityTests.swift`

**Interfaces:**
- Produces: `OutcomeKey.goodMood`; `EvidenceConfig.goodMoodThreshold == 3`; `OutcomeSource` emits `.goodMood` for a mood event `≥ 3`; `EdgeIdentity` round-trips `goodMood` (`"mood:good"` / `("mood","good")`). Task 2 consumes the `"mood"/"good"` columns via phrasing.

- [ ] **Step 1: Update the failing tests first.**

In `ExposureSourceTests.swift`, **change the third event in `extractsSymptomsAndLowMood`** (currently value `3` commented "Good → skipped") to value `2` so it stays a non-outcome and the `count == 2` still holds:

```swift
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .mood,
                        subtype: "mood", value: 2, source: .manual),           // Okay → neither
```

Then **add** a good-mood test to `OutcomeSourceTests`:

```swift
    @Test func goodMoodAtThreshold() {
        let good = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                               subtype: "mood", value: 3, source: .manual)   // Good → good mood
        let okay = HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                               subtype: "mood", value: 2, source: .manual)   // Okay → neither
        let occ = OutcomeSource(config: .default).occurrences(from: [good, okay])
        #expect(occ.filter { $0.key == .goodMood }.count == 1)
        #expect(occ.count == 1)
    }
```

In `EdgeIdentityTests.swift`, add a `goodMood` round-trip to `derivedExposuresRoundTrip` (after the existing lines):

```swift
        roundTrip(.object(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, .food), .goodMood)
```

and add a columns test:

```swift
    @Test func goodMoodColumns() {
        let cols = EdgeIdentity.columns(from: .derived(.shortSleep), to: .goodMood)
        #expect(cols.toCategory == "mood")
        #expect(cols.toSubtype == "good")
        #expect(EdgeIdentity.parse(Relationship(
            fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
            toCategory: cols.toCategory, type: .possibleTrigger, firstSeen: Date(), lastSeen: Date(),
            lastRecomputed: Date(), status: .active,
            edgeKey: EdgeIdentity.edgeKey(from: .derived(.shortSleep), to: .goodMood, type: .possibleTrigger),
            toSubtype: cols.toSubtype))?.outcome == .goodMood)
    }
```

- [ ] **Step 2: Run the tests to confirm they fail.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -20`
Expected: FAIL — `OutcomeKey` has no `.goodMood`; `goodMoodThreshold` undefined.

- [ ] **Step 3: Add `OutcomeKey.goodMood`.** In `ExposureModel.swift`:

```swift
public enum OutcomeKey: Sendable, Equatable, Hashable {
    case symptom(String)   // subtype
    case lowMood
    case goodMood
}
```

- [ ] **Step 4: Add the threshold.** In `EvidenceConfig.swift`, directly under the `lowMoodThreshold` line (18):

```swift
    public var goodMoodThreshold: Double = 3             // mood value ≥ 3 (Good on the 1–3 scale) → good mood
```

- [ ] **Step 5: Mine both mood outcomes.** In `OutcomeSource.swift`, replace the `.mood` case (lines 16-19):

```swift
            case .mood:
                guard let v = e.value else { return nil }
                if v <= config.lowMoodThreshold {
                    return OutcomeOccurrence(key: .lowMood, timestamp: e.timestamp,
                                             value: v, sourceEventID: e.id)
                }
                if v >= config.goodMoodThreshold {
                    return OutcomeOccurrence(key: .goodMood, timestamp: e.timestamp,
                                             value: v, sourceEventID: e.id)
                }
                return nil
```

- [ ] **Step 6: Wire edge identity.** In `EdgeIdentity.swift`:
  - In `toToken`, add after the `.lowMood` case: `case .goodMood: return "mood:good"`.
  - In `columns`, add after the `.lowMood` case: `case .goodMood: return (fromObjectID, fromCategory, "mood", "good")`.
  - In `parseTo`, add after the `mood:low` line: `if token == "mood:good" { return .goodMood }`.

- [ ] **Step 7: Run the full core suite.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -20`
Expected: all pass (incl. the new `goodMoodAtThreshold`, `goodMoodColumns`, and the adjusted `extractsSymptomsAndLowMood`). Report counts.

- [ ] **Step 8: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/OutcomeSource.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EdgeIdentityTests.swift
git commit -m "feat(core): OutcomeKey.goodMood — mine what lifts your mood (mood value ≥ 3) + edge identity"
```

---

### Task 2: Core — mood phrasing + un-suppress the feed

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift` (`claim` mood branch, `subline` mood guard, new `outcomeLabel(for:)`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift` (remove the mood filter)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/InsightPhrasingTests.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/InsightsFeedTests.swift`

**Interfaces:**
- Consumes: mood edges carry `relationship.toCategory == "mood"`, `toSubtype ∈ {"low","good"}` (from Task 1's identity).
- Produces: `InsightPhrasing.claim` renders mood templates; `InsightPhrasing.outcomeLabel(for:) -> String` (mood noun) for Task 3's resolver; mood edges appear in `InsightsFeed.build`.

- [ ] **Step 1: Write the failing tests first.**

In `InsightPhrasingTests.swift`, add a mood fixture helper + tests (the existing `rel()` hardcodes `toCategory: "symptom"`, so build a mood relationship):

```swift
    func moodRel(_ subtype: String, _ type: RelationshipType, lagHours: Double? = 12) -> Relationship {
        Relationship(fromCategory: "shortSleep", toCategory: "mood", type: type,
                     evidenceCount: 6, contradictionCount: 2, confidence: 0.6,
                     strength: 5, lagHours: lagHours, firstSeen: now, lastSeen: now,
                     lastRecomputed: now, status: .active, edgeKey: "k", toSubtype: subtype)
    }
    func moodResolved(_ r: Relationship, exposure: String) -> ResolvedRelationship {
        ResolvedRelationship(relationship: r, exposureLabel: exposure,
                             outcomeLabel: InsightPhrasing.outcomeLabel(for: r),
                             exposureCategory: .food, recentOutcomes: [])
    }

    @Test func moodClaims() {
        #expect(InsightPhrasing.claim(moodResolved(moodRel("good", .possibleTrigger), exposure: "Exercise"))
                == "Exercise seems to lift your mood")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("low", .improves), exposure: "Magnesium"))
                == "Magnesium seems to protect against low moods")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("low", .possibleTrigger), exposure: "Short sleep"))
                == "Short sleep is linked to lower mood")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("good", .improves), exposure: "Alcohol"))
                == "Alcohol seems to weigh on your mood")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("low", .noEffect), exposure: "Coffee"))
                == "No clear link between Coffee and your mood")
    }
    @Test func moodOutcomeLabelIsANaturalNoun() {
        #expect(InsightPhrasing.outcomeLabel(for: moodRel("good", .possibleTrigger)) == "a good mood")
        #expect(InsightPhrasing.outcomeLabel(for: moodRel("low", .possibleTrigger)) == "a low mood")
    }
    @Test func moodTriggerSublineHasLagButNoSeverity() {
        let sub = InsightPhrasing.subline(moodResolved(moodRel("low", .possibleTrigger), exposure: "Short sleep"))
        #expect(sub != nil)
        #expect(sub!.contains("~12h"))
        #expect(!sub!.contains("severity"))   // severity is a symptom concept, omitted for mood
    }
```

In `InsightsFeedTests.swift`, **replace** `moodOutcomeEdgesAreSuppressed` with the inverted test (same two fixtures — a "Dairy" symptom edge + a "Coffee" mood edge — now BOTH appear):

```swift
    @Test func moodOutcomeEdgesNowAppear() {
        let refNow = Date(timeIntervalSince1970: 1_700_000_000)
        func rel(toCategory: String, toSubtype: String, key: String) -> Relationship {
            Relationship(fromCategory: "food", toCategory: toCategory, type: .possibleTrigger,
                         evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
                         firstSeen: refNow.addingTimeInterval(-5 * 86_400), lastSeen: refNow,
                         lastRecomputed: refNow, status: .active, edgeKey: key, toSubtype: toSubtype)
        }
        let dairy = ResolvedRelationship(
            relationship: rel(toCategory: "symptom", toSubtype: "bloating", key: "k-dairy"),
            exposureLabel: "Dairy", outcomeLabel: "bloating", exposureCategory: .food, recentOutcomes: [])
        let coffeeMood = ResolvedRelationship(
            relationship: rel(toCategory: "mood", toSubtype: "low", key: "k-coffee-mood"),
            exposureLabel: "Coffee", outcomeLabel: "a low mood", exposureCategory: .food, recentOutcomes: [])
        let claims = InsightsFeed.build([dairy, coffeeMood], now: refNow)
            .sections.flatMap(\.cards).map { $0.claim.lowercased() }
        #expect(claims.contains { $0.contains("dairy") })     // symptom edge
        #expect(claims.contains { $0.contains("coffee") })    // mood edge now surfaces
        #expect(claims.count == 2)
    }
```

- [ ] **Step 2: Run to confirm failure.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -20`
Expected: FAIL — `outcomeLabel(for:)` undefined; mood claim renders the generic "Coffee → low"; the old suppression is gone but the phrasing/feed aren't updated yet.

- [ ] **Step 3: Add the mood phrasing.** In `InsightPhrasing.swift`, replace `claim(_:)` and `subline(_:)`, and add `outcomeLabel(for:)`:

```swift
    public static func claim(_ rr: ResolvedRelationship) -> String {
        if rr.relationship.toCategory == "mood" { return moodClaim(rr) }
        switch rr.relationship.type {
        case .improves: return "\(rr.exposureLabel) → fewer \(rr.outcomeLabel)"
        case .noEffect: return "No measurable effect of \(rr.exposureLabel) on \(rr.outcomeLabel)"
        default:        return "\(rr.exposureLabel) → \(rr.outcomeLabel)"
        }
    }

    /// Warm, tentative, directional — never causal. `.improves` reduces the outcome;
    /// everything else (possibleTrigger/worsens/precedes) increases it.
    private static func moodClaim(_ rr: ResolvedRelationship) -> String {
        let x = rr.exposureLabel
        let isGood = (rr.relationship.toSubtype == "good")
        switch rr.relationship.type {
        case .noEffect: return "No clear link between \(x) and your mood"
        case .improves: return isGood ? "\(x) seems to weigh on your mood"
                                      : "\(x) seems to protect against low moods"
        default:        return isGood ? "\(x) seems to lift your mood"
                                      : "\(x) is linked to lower mood"
        }
    }

    /// The outcome noun for supporting lines (countLine). Mood reads naturally
    /// ("a good mood"); other outcomes keep their subtype.
    public static func outcomeLabel(for r: Relationship) -> String {
        guard r.toCategory == "mood" else { return r.toSubtype ?? "outcome" }
        return r.toSubtype == "good" ? "a good mood" : "a low mood"
    }
```

And in `subline(_:)`, guard the severity clause for mood (replace the `if let s = r.strength` line):

```swift
        if r.toCategory != "mood", let s = r.strength { parts.append(String(format: "avg severity +%.1f", s)) }
```

- [ ] **Step 4: Un-suppress the feed.** In `InsightsFeed.swift`, delete the mood-filter lines (the two-line comment + the `let resolved = resolved.filter { $0.relationship.toCategory != "mood" }` line). `build` now uses its `resolved` parameter directly.

- [ ] **Step 5: Run the full core suite.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -20`
Expected: all pass (incl. the new mood phrasing tests, the inverted feed test, and the still-green `noCausalLanguage`/`triggerClaimBadgeSublineCountLine`). Report counts.

- [ ] **Step 6: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightPhrasingTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightsFeedTests.swift
git commit -m "feat(core): tentative mood phrasing (lift/lower/protect) + un-suppress mood edges from the feed"
```

---

### Task 3: App — resolver uses the mood outcome noun

**Files:**
- Modify: `Views/HealthOS/Insights/InsightsViewModel.swift` (the `load()` resolver)

**Interfaces:**
- Consumes: `InsightPhrasing.outcomeLabel(for:)` from Task 2.

- [ ] **Step 1: Use the core helper in the resolver.** In `InsightsViewModel.swift`'s `load()`, change the `ResolvedRelationship` construction's `outcomeLabel:` argument from `r.toSubtype ?? "outcome"` to:

```swift
                                                 outcomeLabel: InsightPhrasing.outcomeLabel(for: r),
```

(No other change — mood edges now get "a low mood"/"a good mood"; symptom edges are unchanged since `outcomeLabel(for:)` returns `r.toSubtype ?? "outcome"` for non-mood.)

- [ ] **Step 2: Build + regression.**

Run:
```
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

Run:
```
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests/InsightsViewModelTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|✔ Test|✘ Test|TEST (SUCCEEDED|FAILED)" | tail -10
```
Expected: `** TEST SUCCEEDED **` (the resolver change is behavior-preserving for the existing symptom-based tests).

- [ ] **Step 3: Commit.**

```bash
git add "Views/HealthOS/Insights/InsightsViewModel.swift"
git commit -m "feat(app): Insights resolver renders mood outcomes as a natural noun (a low/good mood)"
```

---

### Task 4: End-to-end verification + regression

**Files:** none (verification).

- [ ] **Step 1: Full regression.**
  - Core: `cd HealthGraphCore && swift test 2>&1 | tail -3` → all green.
  - App target: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known `SwiftDataMigratorTests` teardown crash.
  - App build succeeds.

- [ ] **Step 2: On-device / simulator behavior check** (device preferred). With seeded data + recompute (via the debug view):
  - A **good-mood** edge surfaces as **"… seems to lift your mood"**; a **low-mood** edge as **"… is linked to lower mood"** (and a protective one as "… seems to protect against low moods").
  - Mood cards show badges + dots + drill-down like symptom cards; the supporting line reads "In K of your last N … logs, a good mood followed".
  - **"Pressure drop → lower mood"** can appear (pressure is already an exposure) — the one outside-factor that works this round.
  - **No moon / mercury factor appears** in Insights.
  - Logging **Rough** still shows no crisis takeover; capture surfaces unchanged.
  - Light + dark; XXL Dynamic Type.

- [ ] **Step 3: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- The engine mines a **good-mood** outcome (mood value ≥ 3) alongside low-mood; a mood event maps to at most one outcome (Rough→low, Okay→none, Good→good); `goodMood` round-trips through edge identity.
- Mood edges are **no longer suppressed** — both "what lifts" and "what lowers" surface in the Insights feed, positive-led, with **tentative, non-causal** phrasing ("seems to lift", "is linked to lower", "seems to protect"); supporting lines read with a natural mood noun.
- Barometric pressure (already an exposure) can surface as a mood factor this round; moon/mercury/weather do NOT (next round).
- Core (`OutcomeKey`, threshold, `OutcomeSource`, `EdgeIdentity`, `InsightPhrasing`, `InsightsFeed`) unit-tested; the app resolver wired + regression-green; verified end-to-end.
- No new exposures, no plausibility-tier UI, no re-sort, no capture/crisis/gate changes. The outside-factors + honest-tiering round remains the committed next feature.
