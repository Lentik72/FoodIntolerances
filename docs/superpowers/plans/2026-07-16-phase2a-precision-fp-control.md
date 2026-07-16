# Phase 2A Precision — False-Positive Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Stop the engine from marking weak chance-correlations as `active` by adding a one-sided binomial significance test per pair + Benjamini-Hochberg FDR across all pairs; non-significant directional edges are capped at `candidate`. Validated by a strengthened precision acceptance test (active edges ⊆ planted pairs).

**Architecture:** Two new pure helpers (`SignificanceTester.pValue`, `SignificanceTester.benjaminiHochbergThreshold`); `PairStats` surfaces the per-day contingency it already computes; `RelationshipClassifier` gains a `tailDirection(stats:)` helper and a `significant: Bool` param (non-significant → `candidate`); `EvidenceEngine.recompute` becomes two passes (score+collect p-values → BH threshold → classify). No change to extraction, lag windows, the confidence formula, decay, edge identity, or the noEffect rule.

**Tech Stack:** Swift 5.9+, GRDB, Swift Testing. Package: `HealthGraphCore`. Branch: `phase2a-evidence-engine`.

## Global Constraints

- **Test framework is Swift Testing** (`import Testing`, `@Test`, `#expect`, `@testable import HealthGraphCore`), struct-based, in-memory DB via `try AppDatabase.inMemory()`. NOT XCTest.
- **Determinism:** no `Date()`/random for logic; `now` is injected. Significance math uses `lgamma`/`exp`/`log` (deterministic). BH sorts p-values (deterministic).
- **Significance gates ACTIVATION ONLY.** A non-significant directional pair is capped at `candidate` (its type is still recorded). It must NEVER downgrade a `decayed` edge, alter `confirmedNoEffect`, or touch the confidence formula / decay / confounder logic.
- **`noEffect`/`confirmedNoEffect` is NOT significance-gated** (decided before direction; guarded by the ≥20-exposures/≥90-days rule).
- Do not change extraction, lag windows, the confidence formula, edge identity, migrations, or the confounder/decay stages.
- Build/test: `cd HealthGraphCore && swift test` (scope with `--filter <TypeName>` while iterating; full suite once before committing).
- **Base rate `p0` is clamped to `[1e-9, 1-1e-9]`** before any `log`.

---

## File Structure

**New:** `Evidence/SignificanceTester.swift` (+ `TailDirection`), `Tests/.../SignificanceTesterTests.swift`.
**Modified:** `Evidence/CooccurrenceAnalyzer.swift` (2 fields on `PairStats`), `Evidence/RelationshipClassifier.swift` (`tailDirection` + `significant` param), `Evidence/EvidenceConfig.swift` (`fdrAlpha`), `Evidence/EvidenceEngine.swift` (two-pass recompute), and the test helpers/suites that construct `PairStats` or call `classify`.

---

## Task P1: Surface the per-day contingency on `PairStats`

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CooccurrenceAnalyzer.swift`
- Modify (test helpers that build `PairStats`): `HealthGraphCore/Tests/HealthGraphCoreTests/ConfidenceScorerTests.swift`, `HealthGraphCoreTests/RelationshipClassifierTests.swift`
- Test: `HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift`

**Interfaces:**
- Produces: `PairStats.exposureDayCount: Int`, `PairStats.exposureDaysWithOutcome: Int` (the significance test's `n` and `a`). `baseRate` (already present) is `p0`.

- [ ] **Step 1: Write the failing test** — append to `CooccurrenceAnalyzerTests.swift` (inside `struct CooccurrenceAnalyzerTests`):

```swift
@Test func surfacesPerDayContingency() {
    let day = 86_400.0, base = 1_700_000_000.0
    let exposures = [0, 1, 2].map {
        ExposureOccurrence(key: .object(UUID(), .food),
                           timestamp: Date(timeIntervalSince1970: base + Double($0) * day + 9 * 3600),
                           timezoneID: "UTC", sourceEventID: UUID())
    }
    let outcomes = [
        OutcomeOccurrence(key: .symptom("bloating"),
                          timestamp: Date(timeIntervalSince1970: base + 0 * day + 15 * 3600),
                          value: 5, sourceEventID: UUID()),
        OutcomeOccurrence(key: .symptom("bloating"),
                          timestamp: Date(timeIntervalSince1970: base + 2 * day + 11 * 3600),
                          value: 7, sourceEventID: UUID()),
    ]
    let obs = DateInterval(start: Date(timeIntervalSince1970: base),
                           end: Date(timeIntervalSince1970: base + 3 * day))
    let stats = CooccurrenceAnalyzer(config: .default)
        .analyze(exposure: exposures, outcome: outcomes, window: 0...24, observation: obs)
    #expect(stats?.exposureDayCount == 3)          // 3 distinct exposure days
    #expect(stats?.exposureDaysWithOutcome == 2)   // days 0 and 2 had the outcome in-window
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter CooccurrenceAnalyzerTests`
Expected: FAIL — `PairStats` has no `exposureDayCount`.

- [ ] **Step 3: Add the fields to `PairStats`** — in `CooccurrenceAnalyzer.swift`, add two properties at the END of the `PairStats` struct (after `pairs`):

```swift
    public let pairs: [ExposurePairDetail]
    public let exposureDayCount: Int          // distinct exposure days (n for the significance test)
    public let exposureDaysWithOutcome: Int   // exposure days with the outcome in-window (a)
```

- [ ] **Step 4: Populate them in `analyze`** — the locals already exist (`exposureDays`, `exposureDaysWithOutcome`). Change the `return PairStats(...)` to pass them (append at the end, matching declaration order):

```swift
        return PairStats(exposureCount: exposure.count, followCount: followCount,
                         missCount: exposure.count - followCount, baseRate: baseRate, ratio: ratio,
                         avgEffect: avgEffect, medianLagHours: medianLag,
                         firstExposure: times.first!, lastExposure: times.last!, pairs: pairs,
                         exposureDayCount: exposureDays.count,
                         exposureDaysWithOutcome: exposureDaysWithOutcome)
```

- [ ] **Step 5: Fix the two test helpers that build `PairStats` directly.** In `ConfidenceScorerTests.swift`, the `stats(...)` helper's `PairStats(...)` call must append the two new args:

```swift
        return PairStats(exposureCount: exposures, followCount: follows, missCount: exposures - follows,
                  baseRate: baseRate, ratio: 3, avgEffect: 5, medianLagHours: 6,
                  firstExposure: Date(timeIntervalSince1970: 0), lastExposure: lastExposure, pairs: [],
                  exposureDayCount: exposures, exposureDaysWithOutcome: follows)
```

In `RelationshipClassifierTests.swift`, the `stats(...)` helper likewise:

```swift
        return PairStats(exposureCount: exposures, followCount: exposures / 2, missCount: exposures / 2,
                         baseRate: 0.1, ratio: ratio, avgEffect: 5, medianLagHours: 6,
                         firstExposure: first, lastExposure: last, pairs: [],
                         exposureDayCount: exposures, exposureDaysWithOutcome: exposures / 2)
```

- [ ] **Step 6: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter CooccurrenceAnalyzerTests` then `--filter ConfidenceScorerTests` then `--filter RelationshipClassifierTests`
Expected: PASS (new test + the two helper-using suites compile and pass).

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/CooccurrenceAnalyzer.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ConfidenceScorerTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipClassifierTests.swift
git commit -m "feat(core): surface per-day contingency (exposureDayCount, exposureDaysWithOutcome) on PairStats"
```

---

## Task P2: `SignificanceTester` — binomial p-value + Benjamini-Hochberg threshold

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/SignificanceTester.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/SignificanceTesterTests.swift`

**Interfaces:**
- Produces: `enum TailDirection { case upper, lower }`; `SignificanceTester.pValue(successes:trials:baseRate:direction:) -> Double`; `SignificanceTester.benjaminiHochbergThreshold(pValues:alpha:) -> Double`.
- `pValue`: one-sided binomial tail (`upper` = P(X ≥ a), `lower` = P(X ≤ a)) with X ~ Binomial(n, p0), log-space. `n == 0` → 1.0.
- `benjaminiHochbergThreshold`: the largest p that is significant at FDR `alpha` (0 if none). Rule the engine applies: `significant = pValue <= threshold`.

- [ ] **Step 1: Write the failing tests** — create `SignificanceTesterTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct SignificanceTesterTests {
    @Test func strongLiftIsTinyPValue() {
        // 30/30 successes when background is 5% → astronomically significant.
        let p = SignificanceTester.pValue(successes: 30, trials: 30, baseRate: 0.05, direction: .upper)
        #expect(p < 1e-6)
    }
    @Test func atExpectationIsLargePValue() {
        // a == n*p0 → roughly a coin-flip's worth of tail, not significant.
        let p = SignificanceTester.pValue(successes: 10, trials: 100, baseRate: 0.10, direction: .upper)
        #expect(p > 0.3)
    }
    @Test func handChecked_n10_a8_p0_20_upper() {
        // P(Binomial(10, 0.2) >= 8) = 0.0000779... (sum of k=8,9,10).
        let p = SignificanceTester.pValue(successes: 8, trials: 10, baseRate: 0.20, direction: .upper)
        #expect(abs(p - 0.0000779) < 1e-5)
    }
    @Test func lowerTailForProtective() {
        // Far FEWER successes than background → significant in the lower tail.
        let p = SignificanceTester.pValue(successes: 1, trials: 100, baseRate: 0.30, direction: .lower)
        #expect(p < 1e-6)
    }
    @Test func zeroTrialsIsOne() {
        #expect(SignificanceTester.pValue(successes: 0, trials: 0, baseRate: 0.1, direction: .upper) == 1.0)
    }
    @Test func bhThresholdPicksLargestPassingP() {
        // m=4, alpha=0.05: bounds are .0125, .025, .0375, .05.
        // sorted p = [0.001, 0.01, 0.2, 0.9]; 0.001<=.0125 ✓, 0.01<=.025 ✓, 0.2>.0375, 0.9>.05.
        // Largest passing p = 0.01.
        let t = SignificanceTester.benjaminiHochbergThreshold(pValues: [0.9, 0.2, 0.01, 0.001], alpha: 0.05)
        #expect(abs(t - 0.01) < 1e-12)
    }
    @Test func bhThresholdZeroWhenNonePass() {
        let t = SignificanceTester.benjaminiHochbergThreshold(pValues: [0.5, 0.9], alpha: 0.05)
        #expect(t == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter SignificanceTesterTests`
Expected: FAIL — `SignificanceTester` undefined.

- [ ] **Step 3: Implement `SignificanceTester.swift`:**

```swift
import Foundation

/// Which tail of the binomial we test: a trigger over-produces the outcome
/// (upper), a protective effect under-produces it (lower).
public enum TailDirection: Sendable, Equatable { case upper, lower }

/// Engine-side false-positive control. Deterministic; all math in log-space.
public enum SignificanceTester {
    /// One-sided binomial tail: with X ~ Binomial(n, p0), returns P(X >= a) for
    /// `.upper` and P(X <= a) for `.lower`. `n == 0` → 1.0 (no evidence).
    public static func pValue(successes a: Int, trials n: Int, baseRate p0: Double,
                              direction: TailDirection) -> Double {
        guard n > 0 else { return 1.0 }
        let clampedA = min(max(a, 0), n)
        let p = min(max(p0, 1e-9), 1 - 1e-9)
        let lnP = log(p), ln1mP = log(1 - p)
        func logPMF(_ k: Int) -> Double {
            lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))
                + Double(k) * lnP + Double(n - k) * ln1mP
        }
        let ks: [Int]
        switch direction {
        case .upper: ks = Array(clampedA...n)
        case .lower: ks = Array(0...clampedA)
        }
        let total = ks.reduce(0.0) { $0 + exp(logPMF($1)) }
        return min(1.0, max(0.0, total))
    }

    /// Benjamini-Hochberg: the largest p-value that is significant at FDR `alpha`.
    /// Returns 0 when nothing qualifies. Caller: `significant = pValue <= threshold`.
    public static func benjaminiHochbergThreshold(pValues: [Double], alpha: Double) -> Double {
        let m = pValues.count
        guard m > 0 else { return 0 }
        var threshold = 0.0
        for (i, p) in pValues.sorted().enumerated() {   // rank = i + 1
            if p <= Double(i + 1) / Double(m) * alpha { threshold = p }
        }
        return threshold
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter SignificanceTesterTests`
Expected: PASS (7 tests). If `handChecked_n10_a8_p0_20_upper` is off, re-derive by hand — the code is correct; the expected constant `0.0000779` is `C(10,8)·0.2^8·0.8^2 + C(10,9)·0.2^9·0.8 + 0.2^10`.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/SignificanceTester.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/SignificanceTesterTests.swift
git commit -m "feat(core): SignificanceTester — one-sided binomial p-value + Benjamini-Hochberg threshold"
```

---

## Task P3: `RelationshipClassifier` — `tailDirection` helper + `significant` gate

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/RelationshipClassifier.swift`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipClassifierTests.swift`

**Interfaces:**
- Consumes: `TailDirection` (Task P2), `PairStats` (Task P1).
- Produces: `RelationshipClassifier.tailDirection(stats:) -> TailDirection?` (upper if `ratio >= candidateRatioTrigger`; lower if `ratio <= candidateRatioProtective` && `followCount >= 1`; else nil). `classify(stats:confidence:significant:now:) -> ClassifiedEdge?` — signature gains `significant: Bool`; when a directional type is assigned and `significant == false`, the status is forced to `.candidate` (never `.active`); `.decayed` and `confirmedNoEffect` are unaffected.

- [ ] **Step 1: Update existing tests + add gating tests.** In `RelationshipClassifierTests.swift`: (a) every existing `c.classify(stats:..., confidence:..., now: now)` call gains `significant: true` (they test the direction/status ladder assuming significance). (b) add:

```swift
@Test func nonSignificantTriggerIsCappedToCandidate() {
    let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                       confidence: 0.6, significant: false, now: now)
    #expect(e?.type == .possibleTrigger)
    #expect(e?.status == .candidate)   // would be .active if significant
}
@Test func significantTriggerActivatesNormally() {
    let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                       confidence: 0.6, significant: true, now: now)
    #expect(e?.status == .active)
}
@Test func nonSignificantDoesNotResurrectDecayed() {
    // low confidence → decayed regardless of significance.
    let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                       confidence: 0.2, significant: false, now: now)
    #expect(e?.status == .decayed)
}
@Test func noEffectIgnoresSignificance() {
    let e = c.classify(stats: stats(ratio: 1.0, exposures: 25, spanDays: 120),
                       confidence: 0.1, significant: false, now: now)
    #expect(e?.status == .confirmedNoEffect)
}
@Test func tailDirectionByRatio() {
    #expect(c.tailDirection(stats: stats(ratio: 3, exposures: 10, spanDays: 30)) == .upper)
    #expect(c.tailDirection(stats: stats(ratio: 0.4, exposures: 10, spanDays: 30)) == .lower)
    #expect(c.tailDirection(stats: stats(ratio: 1.0, exposures: 10, spanDays: 30)) == nil)
}
```

(Note: `stats(ratio: 0.4, ...)` has `followCount = exposures/2 = 5 ≥ 1`, so `.lower` is returned.)

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter RelationshipClassifierTests`
Expected: FAIL — `classify` has no `significant:` param; `tailDirection` undefined.

- [ ] **Step 3: Implement the change** in `RelationshipClassifier.swift`. Add the helper and the `significant` param:

```swift
    /// The tail to test for significance, mirroring the activation direction.
    /// nil for noEffect-band / weak-undirected pairs (which are never significance-gated).
    public func tailDirection(stats: PairStats) -> TailDirection? {
        if stats.ratio >= config.candidateRatioTrigger { return .upper }
        if stats.ratio <= config.candidateRatioProtective && stats.followCount >= 1 { return .lower }
        return nil
    }

    public func classify(stats: PairStats, confidence: Double,
                         significant: Bool, now: Date) -> ClassifiedEdge? {
        let spanDays = stats.lastExposure.timeIntervalSince(stats.firstExposure) / 86_400
        if stats.exposureCount >= config.noEffectMinExposures,
           spanDays >= config.noEffectMinSpanDays,
           config.noEffectRatioBand.contains(stats.ratio) {
            return ClassifiedEdge(type: .noEffect, status: .confirmedNoEffect)
        }
        let type: RelationshipType?
        if stats.ratio >= config.candidateRatioTrigger {
            type = .possibleTrigger
        } else if stats.ratio <= config.candidateRatioProtective && stats.followCount >= 1 {
            type = .improves
        } else {
            type = nil
        }
        guard let type else { return nil }
        var status: RelStatus =
            confidence >= config.activationThreshold ? .active
            : confidence < config.decayThreshold ? .decayed
            : .candidate
        // Significance gates activation only: a non-significant edge may not be active.
        if !significant && status == .active { status = .candidate }
        return ClassifiedEdge(type: type, status: status)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter RelationshipClassifierTests`
Expected: PASS (all existing + 5 new).

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/RelationshipClassifier.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipClassifierTests.swift
git commit -m "feat(core): RelationshipClassifier — tailDirection helper + significance gate (non-significant → candidate)"
```

---

## Task P4: `EvidenceEngine.recompute` — two-pass significance gate

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (add `fdrAlpha`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift`
- Test: existing `HealthGraphCoreTests/EvidenceEngineTests.swift` must still pass (no new test here; Task P5 adds the acceptance oracle)

**Interfaces:**
- Consumes: `SignificanceTester`, `classify(...significant:...)`, `tailDirection`, `PairStats` fields, `config.fdrAlpha`.
- Restructures `recompute` into: score+collect p-values → BH threshold → classify+build. Upsert/reconcile unchanged.

- [ ] **Step 1: Add `fdrAlpha` to `EvidenceConfig`** — in `EvidenceConfig.swift`, after `observationalCeiling`:

```swift
    public var observationalCeiling = 0.75
    public var fdrAlpha = 0.05   // Benjamini-Hochberg false-discovery rate for activation
```

- [ ] **Step 2: Rewrite the candidate loop in `recompute`.** Locate the existing single loop (`var computed: [String: Relationship] = [:]` … `for cand in candidates { … computed[key] = rel }`) and replace it with two passes. Everything BEFORE it (event load, extract, daySets, illness, candidates, analyzer/confounder/scorer/classifier construction) and everything AFTER it (the `existing`/`existingByKey` upsert + reconcile + `save` + `RecomputeReport`) stays exactly as-is.

```swift
        // Pass 1 — score every candidate; collect p-values for the directional ones.
        var scored: [(cand: Candidate, stats: PairStats, conf: Double, pValue: Double?)] = []
        var pValues: [Double] = []
        for cand in candidates {
            guard let exp = exposures[cand.exposure], let out = outcomes[cand.outcome] else { continue }
            let window = config.lagWindow(for: cand.exposure)
            guard let stats = analyzer.analyze(exposure: exp, outcome: out,
                                               window: window, observation: observation) else { continue }
            var others = daySets.filter { $0.key != cand.exposure }
            if !illness.isEmpty { others[Self.illnessConfounderKey] = illness }
            let (penalty, _) = confounder.penalty(targetDays: daySets[cand.exposure] ?? [], others: others)
            let conf = scorer.confidence(stats: stats, confounderPenalty: penalty, now: now)
            var p: Double? = nil
            if let dir = classifier.tailDirection(stats: stats) {
                let pv = SignificanceTester.pValue(successes: stats.exposureDaysWithOutcome,
                                                   trials: stats.exposureDayCount,
                                                   baseRate: stats.baseRate, direction: dir)
                p = pv
                pValues.append(pv)
            }
            scored.append((cand, stats, conf, p))
        }

        // Multiple-comparison control across all directional pairs this run.
        let bhThreshold = SignificanceTester.benjaminiHochbergThreshold(pValues: pValues, alpha: config.fdrAlpha)

        // Pass 2 — classify with the significance verdict, build edges.
        var computed: [String: Relationship] = [:]
        for s in scored {
            let significant = s.pValue.map { $0 <= bhThreshold } ?? false
            guard let edge = classifier.classify(stats: s.stats, confidence: s.conf,
                                                 significant: significant, now: now) else { continue }
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

> **Implementer note:** the `Relationship(...)` construction is byte-identical to the pre-existing one (verify against the current file), just reading fields from `s.stats`/`s.conf` instead of the old loop locals. Do not change the upsert/reconcile block that follows.

- [ ] **Step 3: Run the engine tests to verify no regression**

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineTests`
Expected: PASS — all 6 engine tests still green (dairy→bloating is hugely significant, so activation is unaffected; decay/dismiss/reconcile/parity untouched). If `minesDairyBloatingAsActiveTrigger` fails, STOP and report — a single strong planted pair must be significant (its p-value ≪ the BH bound for m=1).

- [ ] **Step 4: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift
git commit -m "feat(core): EvidenceEngine — two-pass significance gate (binomial p + BH-FDR) before activation"
```

---

## Task P5: Strengthen the acceptance oracle + validate + tune

**Files:**
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineAcceptanceTests.swift`
- Possibly modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (`fdrAlpha` only, if tuning needed)

**Interfaces:**
- This is the oracle. It replaces the outcome-vocabulary precision check with a **planted-pairs** precision check, and adds the illness-confounder behavioral test (FU-2). Recall + planted-pairs precision + FU-2 + the existing ceiling/determinism/noEffect tests must all pass with the default `fdrAlpha`.

- [ ] **Step 0: Start from the committed acceptance file.** The working tree may contain an earlier uncommitted FU attempt; the controller resets the file to HEAD before this task, so you begin from the committed `EvidenceEngineAcceptanceTests.swift`.

- [ ] **Step 1: Replace `precisionRejectsNoise` with a planted-pairs precision test, and add FU-2.** Remove the old outcome-vocabulary `precisionRejectsNoise` and add:

```swift
@Test func precisionActiveEdgesAreOnlyPlantedPairs() async throws {
    let db = try await minedDB()
    let objects = GRDBObjectStore(database: db)
    let active = try await GRDBRelationshipStore(database: db).relationships(status: .active)
    // (exposure-label, outcome-subtype) pairs the harness actually plants.
    let planted: Set<String> = [
        "dairy|bloating", "shortSleep|fatigue", "pressureDrop|headache",
        "highStress|tension", "cyclePhase.luteal|cramps", "magnesium|migraine",
        "espresso|jitters", "croissant|jitters",
    ]
    for r in active {
        var exposure = r.fromCategory ?? "?"           // derived edges carry the kind here
        if let oid = r.fromObjectID, let o = try await objects.object(id: oid) { exposure = o.name }
        let pair = "\(exposure)|\(r.toSubtype ?? "?")"
        #expect(planted.contains(pair), "unplanted active edge: \(pair) [conf \(r.confidence)]")
    }
    #expect(!active.isEmpty)
}

@Test func illnessRecordedAsConfounderForOverlappingExposure() async throws {
    let db = try AppDatabase.inMemory()
    let store = GRDBEventStore(database: db)
    let gluten = try await GRDBObjectStore(database: db).findOrCreate(name: "gluten", kind: .food, metadata: nil)
    var events: [HealthEvent] = []
    let base = now.addingTimeInterval(-40 * 86_400)
    for d in 0..<20 {
        let day = base.addingTimeInterval(Double(d) * 86_400)
        events.append(HealthEvent(timestamp: day.addingTimeInterval(9 * 3600), timezoneID: "UTC",
                                  category: .food, subtype: "gluten", objectID: gluten.id, source: .manual))
        events.append(HealthEvent(timestamp: day.addingTimeInterval(15 * 3600), timezoneID: "UTC",
                                  category: .symptom, subtype: "nausea", value: 5, source: .manual))
        if d < 18 {  // illness on 18/20 = 90% of gluten days ( > 60% )
            events.append(HealthEvent(timestamp: day.addingTimeInterval(8 * 3600), timezoneID: "UTC",
                                      category: .illness, subtype: "cold", source: .manual))
        }
    }
    try await store.save(events)
    let engine = EvidenceEngine(database: db)
    _ = try await engine.recompute(asOf: now)
    let edge = try await GRDBRelationshipStore(database: db).all().first { $0.toSubtype == "nausea" }
    #expect(edge != nil)
    let ev = try await engine.evidence(for: edge!, asOf: now)
    #expect(!ev.confounders.isEmpty)   // illness shadows gluten
}
```

- [ ] **Step 2: Run the acceptance suite**

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineAcceptanceTests`
Expected: `recallAllPlantedPatterns`, `precisionActiveEdgesAreOnlyPlantedPairs`, `illnessRecordedAsConfounderForOverlappingExposure`, `confirmedNoEffectForNullSupplement`, `observationalCeilingNeverExceeded`, `confounderIsRecordedForInseparablePair`, `deterministicAcrossRuns` all PASS.

- [ ] **Step 3: If precision or recall fails, tune `fdrAlpha` ONLY.** The default is 0.05. If a *noise* edge still activates, LOWER `fdrAlpha` (stricter). If a *real* planted edge is suppressed to candidate, RAISE it (more lenient). Re-run after each change. Document the BEFORE→AFTER value and which test drove it. **Never** weaken a test assertion or change any stage/algorithm code. If no `fdrAlpha` in `(0, 0.2]` satisfies BOTH recall and precision simultaneously, STOP and report BLOCKED with the offending edge(s) and their p-values — that is a real signal the significance model needs rethinking, not a tuning gap. (Expectation from the design's diagnostic: the default 0.05 already separates them with wide margin; tuning should not be needed.)

- [ ] **Step 4: Full regression**

Run: `cd HealthGraphCore && swift test`
Expected: PASS — entire `HealthGraphCore` suite. The perf tripwire still passes (BH adds an O(m log m) sort over a few dozen pairs).

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineAcceptanceTests.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift
git commit -m "test(core): precision oracle — active edges ⊆ planted pairs (FU-1) + illness-confounder test (FU-2)"
```

---

## Definition of Done

- `swift test` green for the whole `HealthGraphCore` package.
- The engine gates activation on a binomial significance test + Benjamini-Hochberg FDR; non-significant directional edges are `candidate`, not `active`.
- The strengthened precision test proves **active edges' (exposure, outcome) ⊆ the 8 planted pairs** at the default `fdrAlpha` — the ~10 prior false positives (chicken/rice/espresso/croissant→cramps, shortSleep→headache/migraine, pressureDrop→cramps/migraine, luteal→headache, menstrual→cramps) are now `candidate`.
- Recall (all 8 planted active), FU-2 (illness confounder), determinism, ceiling, and noEffect all still pass.
- No change to extraction, lag windows, the confidence formula, decay, edge identity, or migrations.
