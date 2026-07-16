# Phase 2A Precision — Temporal Stability Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add an out-of-sample replication (temporal stability) requirement for activation, so a chance correlation (`chicken→cramps`) that ratio/significance can't catch is capped at `candidate`, while genuine associations (which replicate across both time-halves) stay `active`.

**Architecture:** New pure stage `StabilityValidator` splits a pair's exposures at their median time and reuses `CooccurrenceAnalyzer` on each half, requiring both to be directional in the full-data direction. `RelationshipClassifier.classify` gains a `stable: Bool` param (activation now needs significant AND effect-floor AND stable). The engine computes stability only for significant directional pairs. No change to extraction, lag windows, the confidence formula, significance, the effect-size floors, decay, or edge identity.

**Tech Stack:** Swift 5.9+, GRDB, Swift Testing. Package: `HealthGraphCore`. Branch: `phase2a-evidence-engine`.

## Global Constraints

- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `@testable import HealthGraphCore`), struct-based, in-memory DB. NOT XCTest.
- **Determinism:** no `Date()`/random for logic. Median split is by timestamp (deterministic); the analyzer is pure.
- **Stability gates ACTIVATION ONLY** (alongside significance + effect-floor). It must NOT resurrect a `.decayed` edge, alter `confirmedNoEffect`, or touch any other stage.
- Do not change extraction, lag windows, the confidence formula, significance/BH-FDR, the effect-size floors, decay, edge identity, or migrations.
- Build/test: `cd HealthGraphCore && swift test`.

---

## Task S1: `StabilityValidator` + config

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/StabilityValidator.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/StabilityValidatorTests.swift`

**Interfaces:**
- Produces: `EvidenceConfig.stabilityMinExposuresPerHalf: Int = 5`; `StabilityValidator.isStable(exposure:[ExposureOccurrence], outcome:[OutcomeOccurrence], window:ClosedRange<Double>, fullDirection:TailDirection, config:EvidenceConfig) -> Bool`.
- Stable iff: ≥ `2 * stabilityMinExposuresPerHalf` exposures, split at the median index into early/late (each ≥ `stabilityMinExposuresPerHalf`), and BOTH halves are directional in `fullDirection` (each half's `ratio` past the direction gate). Each half is analyzed as a self-contained mini-dataset over its own exposure span (outcomes filtered to that span + window slack).

- [ ] **Step 1: Add config** — in `EvidenceConfig.swift`, after the activation-ratio floors:

```swift
    public var stabilityMinExposuresPerHalf = 5   // each temporal half must carry this much evidence
```

- [ ] **Step 2: Write the failing tests** — create `StabilityValidatorTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct StabilityValidatorTests {
    let day = 86_400.0, base = 1_700_000_000.0
    let key = ExposureKey.object(UUID(), .food)

    // 20 exposures on days 0..19 at 09:00; outcome follows a chosen subset within 6h.
    func dataset(followDays: Set<Int>) -> ([ExposureOccurrence], [OutcomeOccurrence]) {
        var exp: [ExposureOccurrence] = [], out: [OutcomeOccurrence] = []
        for d in 0..<20 {
            let t = Date(timeIntervalSince1970: base + Double(d) * day + 9 * 3600)
            exp.append(ExposureOccurrence(key: key, timestamp: t, timezoneID: "UTC", sourceEventID: UUID()))
            if followDays.contains(d) {
                out.append(OutcomeOccurrence(key: .symptom("s"),
                    timestamp: t.addingTimeInterval(3 * 3600), value: 5, sourceEventID: UUID()))
            }
        }
        return (exp, out)
    }

    @Test func stableWhenEffectHoldsInBothHalves() {
        // Outcome follows ~80% of exposures across the WHOLE range → both halves directional.
        let (exp, out) = dataset(followDays: Set([0,1,2,3,5,6,7,8,10,11,12,13,15,16,17,18]))
        #expect(StabilityValidator.isStable(exposure: exp, outcome: out, window: 0...24,
                                            fullDirection: .upper, config: .default))
    }

    @Test func unstableWhenEffectOnlyInOneHalf() {
        // Outcome follows only the EARLY half (days 0..9); late half has no follows → not stable.
        let (exp, out) = dataset(followDays: Set(0..<10))
        #expect(!StabilityValidator.isStable(exposure: exp, outcome: out, window: 0...24,
                                             fullDirection: .upper, config: .default))
    }

    @Test func unstableWhenTooFewExposures() {
        // 8 exposures < 2*5 → cannot validate.
        var exp: [ExposureOccurrence] = [], out: [OutcomeOccurrence] = []
        for d in 0..<8 {
            let t = Date(timeIntervalSince1970: base + Double(d) * day + 9 * 3600)
            exp.append(ExposureOccurrence(key: key, timestamp: t, timezoneID: "UTC", sourceEventID: UUID()))
            out.append(OutcomeOccurrence(key: .symptom("s"), timestamp: t.addingTimeInterval(3 * 3600),
                                         value: 5, sourceEventID: UUID()))
        }
        #expect(!StabilityValidator.isStable(exposure: exp, outcome: out, window: 0...24,
                                             fullDirection: .upper, config: .default))
    }
}
```

- [ ] **Step 3: Run to verify failure** — `cd HealthGraphCore && swift test --filter StabilityValidatorTests`. Expected: FAIL (undefined).

- [ ] **Step 4: Implement `StabilityValidator.swift`:**

```swift
import Foundation

/// Out-of-sample replication: a genuine association holds across time; a chance
/// one does not. Splits exposures at their median time and requires BOTH halves
/// to be directional in the full-data direction. Reuses CooccurrenceAnalyzer.
public enum StabilityValidator {
    public static func isStable(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence],
                                window: ClosedRange<Double>, fullDirection: TailDirection,
                                config: EvidenceConfig) -> Bool {
        let sorted = exposure.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 * config.stabilityMinExposuresPerHalf else { return false }
        let mid = sorted.count / 2
        let early = Array(sorted[0..<mid])
        let late = Array(sorted[mid...])
        guard early.count >= config.stabilityMinExposuresPerHalf,
              late.count >= config.stabilityMinExposuresPerHalf else { return false }
        let analyzer = CooccurrenceAnalyzer(config: config)

        func directional(_ half: [ExposureOccurrence]) -> Bool {
            let times = half.map(\.timestamp)
            guard let lo = times.min(), let hi = times.max() else { return false }
            let obsEnd = hi.addingTimeInterval(window.upperBound * 3600)
            let halfOutcomes = outcome.filter { $0.timestamp >= lo && $0.timestamp <= obsEnd }
            guard let stats = analyzer.analyze(exposure: half, outcome: halfOutcomes, window: window,
                                               observation: DateInterval(start: lo, end: obsEnd)) else { return false }
            switch fullDirection {
            case .upper: return stats.ratio >= config.candidateRatioTrigger
            case .lower: return stats.ratio <= config.candidateRatioProtective
            }
        }
        return directional(early) && directional(late)
    }
}
```

- [ ] **Step 5: Run to verify pass** — `cd HealthGraphCore && swift test --filter StabilityValidatorTests`. Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/StabilityValidator.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/StabilityValidatorTests.swift
git commit -m "feat(core): StabilityValidator — temporal-split replication check + stabilityMinExposuresPerHalf"
```

---

## Task S2: Wire stability into the classifier + engine

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/RelationshipClassifier.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipClassifierTests.swift`

**Interfaces:**
- `classify` signature gains `stable: Bool`: `classify(stats:confidence:significant:stable:now:)`. Activation requires `significant && meetsEffectFloor && stable`. The classifier + its caller (engine) change together so the build stays green.
- Engine computes `stable` only for significant directional pairs (via `StabilityValidator`, using the pair's `tailDirection` as `fullDirection`).

- [ ] **Step 1: Update classifier tests + add stability cases.** In `RelationshipClassifierTests.swift`: (a) every existing `c.classify(...)` call gains `stable: true`. (b) add:

```swift
@Test func significantPastFloorButUnstableIsCandidate() {
    let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                       confidence: 0.6, significant: true, stable: false, now: now)
    #expect(e?.type == .possibleTrigger)
    #expect(e?.status == .candidate)   // would be active if stable
}
@Test func significantPastFloorAndStableActivates() {
    let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                       confidence: 0.6, significant: true, stable: true, now: now)
    #expect(e?.status == .active)
}
@Test func unstableDoesNotResurrectDecayed() {
    let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                       confidence: 0.2, significant: true, stable: false, now: now)
    #expect(e?.status == .decayed)
}
@Test func noEffectIgnoresStability() {
    let e = c.classify(stats: stats(ratio: 1.0, exposures: 25, spanDays: 120),
                       confidence: 0.1, significant: false, stable: false, now: now)
    #expect(e?.status == .confirmedNoEffect)
}
```

- [ ] **Step 2: Run to verify failure** — `cd HealthGraphCore && swift test --filter RelationshipClassifierTests`. Expected: FAIL (no `stable:` param).

- [ ] **Step 3: Add `stable` to `classify`** — in `RelationshipClassifier.swift`, add the param and extend the activation guard:

```swift
    public func classify(stats: PairStats, confidence: Double,
                         significant: Bool, stable: Bool, now: Date) -> ClassifiedEdge? {
```

and change the activation line to:

```swift
        if status == .active && (!significant || !meetsEffectFloor || !stable) { status = .candidate }
```

(Everything else in `classify` — noEffect-first, type/direction, effect-floor computation, confidence ladder — stays exactly as is.)

- [ ] **Step 4: Wire stability into `EvidenceEngine.recompute`'s pass 2.** Replace the `significant`/`classify` lines in the pass-2 loop with:

```swift
        for s in scored {
            let significant = s.pValue.map { $0 <= bhThreshold } ?? false
            var stable = false
            if significant, let dir = classifier.tailDirection(stats: s.stats),
               let exp = exposures[s.cand.exposure], let out = outcomes[s.cand.outcome] {
                let window = config.lagWindow(for: s.cand.exposure)
                stable = StabilityValidator.isStable(exposure: exp, outcome: out, window: window,
                                                     fullDirection: dir, config: config)
            }
            guard let edge = classifier.classify(stats: s.stats, confidence: s.conf,
                                                 significant: significant, stable: stable, now: now) else { continue }
            let key = EdgeIdentity.edgeKey(from: s.cand.exposure, to: s.cand.outcome, type: edge.type)
            let cols = EdgeIdentity.columns(from: s.cand.exposure, to: s.cand.outcome)
            let rel = Relationship(
                fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
                toCategory: cols.toCategory, type: edge.type,
                evidenceCount: s.stats.followCount, contradictionCount: s.stats.missCount,
                confidence: s.conf, strength: s.stats.avgEffect, lagHours: s.stats.medianLagHours,
                firstSeen: now, lastSeen: s.stats.lastExposure, lastRecomputed: now,
                status: edge.status, edgeKey: key, toSubtype: cols.toSubtype)
            computed[key] = rel
        }
```

> **Implementer note:** the only changes vs the current pass-2 loop are the `var stable = …` block and the added `stable: stable` argument to `classify`. The `Relationship(...)` construction and the upsert/reconcile block that follows are unchanged — verify against the current file.

- [ ] **Step 5: Run to verify pass** — `cd HealthGraphCore && swift test --filter RelationshipClassifierTests` then `--filter EvidenceEngineTests`. Expected: classifier PASS; the 6 engine tests PASS (the strong dairy→bloating signal replicates across halves → still active; decay/dismiss/reconcile/parity untouched). If `minesDairyBloatingAsActiveTrigger` fails, STOP and report — the seeded dairy→bloating (30 exposures, ~15/half, all followed) must be stable.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/RelationshipClassifier.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipClassifierTests.swift
git commit -m "feat(core): activation requires temporal stability (significant AND floor AND stable)"
```

---

## Task S3: Update the precision oracle + validate

**Files:**
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineAcceptanceTests.swift`
- Possibly modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (`stabilityMinExposuresPerHalf` only, if tuning needed)

**Interfaces:**
- The precision oracle now accepts `active ⊆ planted ∪ {cyclePhase.menstrual|cramps}` (the real cycle correlation). `chicken→cramps` must now be `candidate` (fails stability). Recall (8 planted active) unchanged.

- [ ] **Step 1: Update `precisionActiveEdgesAreOnlyPlantedPairs`** — add the allow-listed cycle correlation to the accepted set:

```swift
    let planted: Set<String> = [
        "dairy|bloating", "shortSleep|fatigue", "pressureDrop|headache",
        "highStress|tension", "cyclePhase.luteal|cramps", "magnesium|migraine",
        "espresso|jitters", "croissant|jitters",
        "cyclePhase.menstrual|cramps",   // real cycle correlation (replicates); allow-listed per stability-gate design §2
    ]
```

Keep the rest of the test body (resolve exposure via `ObjectStore`/`fromCategory`, assert each active pair ∈ `planted`, assert `!active.isEmpty`).

- [ ] **Step 2: Run the acceptance suite** — `cd HealthGraphCore && swift test --filter EvidenceEngineAcceptanceTests`. Expected: all pass — `recallAllPlantedPatterns` (8 planted active), `precisionActiveEdgesAreOnlyPlantedPairs` (active ⊆ planted ∪ menstrual→cramps; `chicken→cramps` now candidate), FU-2, ceiling, noEffect, determinism, espresso/croissant confounder.

- [ ] **Step 3: If `chicken→cramps` is STILL active** (it replicated across both halves), STOP and report BLOCKED with the measured per-half ratios (add a temporary diagnostic that calls `StabilityValidator.isStable` for the chicken/cramps occurrences and prints each half's ratio; remove it before finishing). Do NOT weaken the assertion or add `chicken→cramps` to the allow-list. This is the honest-risk case from the design — surface it. If a *real* planted edge dropped to candidate, tune `stabilityMinExposuresPerHalf` DOWN (document it) and re-run; if no value works, report BLOCKED.

- [ ] **Step 4: Full regression** — `cd HealthGraphCore && swift test`. Expected: whole suite green; the perf tripwire still under bound (stability adds two half-analyses only for would-be-active pairs — a handful per run).

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineAcceptanceTests.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift
git commit -m "test(core): precision oracle — stability drops chicken→cramps; allow-list real menstrual→cramps"
```

---

## Definition of Done

- `swift test` green for the whole `HealthGraphCore` package.
- Activation requires all three gates: significance (BH-FDR @ 0.05), effect-size floor, AND temporal stability (replication in both halves).
- The precision oracle proves `active ⊆ planted ∪ {cyclePhase.menstrual|cramps}` — `chicken→cramps` (the chance FP whose ratio matched a real edge) is now `candidate`; all 8 planted stay `active`.
- No change to extraction, lag windows, the confidence formula, significance, the effect-size floors, decay, edge identity, or migrations.
