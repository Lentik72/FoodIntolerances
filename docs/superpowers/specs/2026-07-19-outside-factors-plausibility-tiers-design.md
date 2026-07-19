# Outside Factors + Honest Plausibility Tiers — Design

**Date:** 2026-07-19
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Mine two already-emitted environmental factors — **full moon** and **mercury retrograde** — as exposures the evidence engine correlates, and introduce a **plausibility-tier framework** so every factor is presented by its causal plausibility. Nothing unproven reads as established science. Cross-cutting: the tier applies to *all* insights (mood + symptoms), keyed on the exposure.

**Not this round:** weather (temperature / humidity) as exposures — those aren't even *captured* yet (they need new weather-API ingestion), so they're the committed **next round** (§8). No new opt-in toggles, no re-sort beyond the new section.

---

## 1. Problem

Leo wants outside/environmental factors — moon, mercury, weather — tracked and correlated, *honestly*: "not proven as fact, but noted and tracked." Today:

- **Moon phase** and **mercury retrograde** are computed and emitted as `.environment` events (`EnvironmentalEventFactory`), and shown in the Timeline — but **no `ExposureSource` mines them**, so the engine never correlates them.
- **Barometric pressure** already *is* a mined exposure (`PressureDropExposureSource`) — established science, works today.
- There is **no way to distinguish a plausible factor from a coincidental one** in the Insights surface. If we simply started mining mercury retrograde, a statistically-significant-but-meaningless correlation would render with the same authority as "short sleep → low mood" — lending false scientific credibility to astrology, a real credibility risk with the clinic design partner.

This round wires moon (as **full moon**) and mercury as exposures **and** adds the tier framework that presents each honestly — the guardrail and the first non-established factors together, so the framework has something to tier.

## 2. Decisions (Leo, 2026-07-19)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Principle | **Track & correlate everything the user wants, but present each factor with an honest plausibility tier** so nothing unproven masquerades as established science. |
| 2 | Three tiers | **Established** (known mechanism) · **Contested** (plausible, weak/mixed evidence) · **Novelty** (no known mechanism). |
| 3 | Tier presentation | Established → normal card (no label). Contested → in the evidence feed with an *"unproven mechanism — your personal pattern"* tag. Novelty → **not** in the evidence feed; a separate **"Just for fun"** section, labeled *"a curious coincidence — correlation isn't causation."* |
| 4 | Which factors | This round adds **full moon** (→ *contested*) and **mercury retrograde** (→ *novelty*). Existing factors stay *established*. |
| 5 | Moon granularity | **Full moon only**, a single exposure. The "Full Moon" phase bucket already spans ~2 days/cycle (~25 days/yr) — enough for the gates, no extra windowing. (Not all 8 phases — that fragments the data.) |
| 6 | Scope | Weather (temp/humidity) deferred to the next round (needs new ingestion). |

## 3. Architecture

### A. Two new exposures (core)

`DerivedExposureKind` (`Evidence/ExposureModel.swift`) gains two cases:

```swift
public enum DerivedExposureKind: Sendable, Equatable, Hashable {
    case shortSleep, highStress, pressureDrop
    case cyclePhase(CyclePhase)
    case fullMoon, mercuryRetrograde   // NEW — outside factors
}
```

Two new `ExposureSource`s (mirroring `PressureDropExposureSource` in `Evidence/DerivedEventExposureSources.swift`), each reading the daily `.environment` events the factory already emits:

- **`FullMoonExposureSource`** — a `.environment` event with `subtype == "moonPhase"` whose `metadata["phase"] == "Full Moon"` → an `ExposureOccurrence(key: .derived(.fullMoon), …)`. (The factory cleans "Full Moon 🌕" → "Full Moon"; the "Full Moon" bucket spans ~2 days/cycle.)
- **`MercuryRetrogradeExposureSource`** — a `.environment` event with `subtype == "mercuryRetrograde"` → `ExposureOccurrence(key: .derived(.mercuryRetrograde), …)`. (Presence event, emitted on retrograde days.)

Both are **registered in the engine's exposure-source list** (wherever `EvidenceEngine` assembles its sources, alongside ShortSleep/PressureDrop/HighStress/CyclePhase) so `recompute` mines them automatically.

**Edge identity** (`Evidence/EdgeIdentity.swift`) — `fromToken`/`parseFrom` gain the two derived tokens (mirroring shortSleep): `.derived(.fullMoon)` ↔ `"derived:fullMoon"`; `.derived(.mercuryRetrograde)` ↔ `"derived:mercuryRetrograde"`. (`columns` already derives `fromCategory` by stripping the `"derived:"` prefix → `"fullMoon"` / `"mercuryRetrograde"`.)

**Lag windows** (`Evidence/EvidenceConfig.swift`) — `lagWindow(for:)` maps the two new kinds to a same-day window (e.g. `0...24`), since these are day-state factors like pressure/stress.

**Phrasing labels** (`Insights/InsightPhrasing.swift`) — `derivedExposureLabel` gains `"fullMoon" → "Full moon"` and `"mercuryRetrograde" → "Mercury retrograde"`.

### B. The plausibility-tier framework (core)

A new pure classifier — the single source of truth for a factor's tier:

```swift
public enum PlausibilityTier: Sendable, Equatable { case established, contested, novelty }

public enum PlausibilityCatalog {
    /// Tier for an exposure, keyed on the resolved `fromCategory` token
    /// (object categories like "food", or derived tokens like "fullMoon").
    public static func tier(forExposureCategory category: String?) -> PlausibilityTier {
        switch category {
        case "fullMoon":          return .contested
        case "mercuryRetrograde": return .novelty
        default:                  return .established   // food/med/supplement/sleep/stress/pressure/cycle
        }
    }
}
```

The tier is a property of the **exposure**, orthogonal to the outcome — a full-moon→headache and a full-moon→low-mood edge are both *contested*; any mercury edge is *novelty*.

### C. Presentation (core feed + app)

- **`InsightsFeed.build`** computes each resolved edge's tier via `PlausibilityCatalog.tier(forExposureCategory: r.relationship.fromCategory)` and:
  - routes **novelty** edges into a new dedicated section (`InsightSectionKind.justForFun`), separate from the evidence sections (active/noEffect/archive);
  - keeps **established** and **contested** edges in the normal sections, attaching the tier to the card model.
- **`InsightCardModel`** gains a `tier: PlausibilityTier` (default `.established`), so the card view can render the contested tag; novelty cards live under the "Just for fun" header.
- **Card view** (`InsightCardView`): a **contested** card shows a small, quiet tag — *"unproven mechanism · your pattern"* — beneath the claim. Novelty cards render in the "Just for fun" section (§below), each with the coincidence framing.
- **The "Just for fun" section** (a new section in the Insights feed, rendered last): header **"Just for fun"** + subtext *"Curious coincidences from your data — correlation isn't causation, and there's no known mechanism."* Only appears when a novelty edge actually passes the gates (no empty section).

## 4. Reused / unchanged

- The **evidence gates** (significance + effect-size + stability) and the **0.75 observational ceiling** are untouched — a coincidental mercury/moon correlation still has to clear them to appear at all, and the tiering is *on top of* that, not a replacement. (Weak astrological correlations mostly won't even pass; the tier framing is the honest belt for the ones that do.)
- **Phrasing** — the existing tentative, non-causal templates (`InsightPhrasing.claim`, mood + symptom) render moon/mercury edges the same way; the tier tag / section is the honesty layer, not new claim copy.
- **The engine's structure**, the mood work, capture, crisis flow — all untouched.

## 5. Copy / honesty guardrails

- **Contested tag:** "unproven mechanism · your pattern" — short, quiet, honest; never hides the factor, just frames it.
- **Novelty section:** "Just for fun — a curious coincidence; correlation isn't causation, and there's no known mechanism." Visible (tracking it has a payoff, and it's honestly entertaining) but firmly outside the evidence cards.
- **No causal language anywhere** (the existing rule + `noCausalLanguage` tests continue to bind).
- The moon/mercury cards still say "seems to" / "is linked to" like everything else — the tier is *added* honesty, never a downgrade of the phrasing rule.

## 6. Testing

- **Core (`swift test`):**
  - `FullMoonExposureSource` — a `moonPhase`/"Full Moon" event yields a `.fullMoon` exposure; a non-full phase does not.
  - `MercuryRetrogradeExposureSource` — a `mercuryRetrograde` event yields a `.mercuryRetrograde` exposure.
  - `EdgeIdentityTests` — both new derived exposures round-trip (`"derived:fullMoon"` / `"derived:mercuryRetrograde"`).
  - `InsightPhrasingTests` — `derivedExposureLabel("fullMoon") == "Full moon"`, `("mercuryRetrograde") == "Mercury retrograde"`.
  - `PlausibilityCatalogTests` — `tier(for: "fullMoon") == .contested`, `("mercuryRetrograde") == .novelty`, `("food") == .established`, `("shortSleep") == .established`, `(nil) == .established`.
  - `InsightsFeedTests` — a novelty (mercury) edge lands in the `.justForFun` section, NOT the active section; a contested (full-moon) edge lands in the active section with `tier == .contested`; an established edge is `.established`. (Extend the existing feed tests.)
  - `EvidenceConfigTests` — `lagWindow(for: .derived(.fullMoon))` / `.mercuryRetrograde` are defined (same-day).
- **App (`-parallel-testing-enabled NO`):** `InsightsViewModelTests` — a seeded contested edge surfaces with its tag; a seeded novelty edge surfaces under "Just for fun" (mirrors the mood VM test, seeding a `Relationship` with the derived `fromCategory`).
- **Device e2e:** a debug **"Load OUTSIDE-FACTORS demo"** seed (full-moon → a symptom, mercury → a symptom, + recompute) so the contested tag + "Just for fun" section render on device; confirm the established factors are unlabeled; confirm the novelty section never carries a bare evidence card. Light + dark.

## 7. Out of scope (this round)

- **Weather (temperature / humidity)** as exposures — needs new weather-API ingestion; the committed next round (§8).
- **Any opt-in / off toggle** for outside factors — they're ambient and only surface when a correlation clears the gates; a settings toggle is YAGNI for now.
- **Re-sorting** the evidence feed — only the new "Just for fun" section is added (rendered last); existing ordering is untouched.
- **Season** as an exposure — it's emitted but out of scope here (would be *established/contested*; not requested this round).
- No changes to the gates, the phrasing rule, capture, or the crisis flow.

## 8. The committed next round — Weather exposures

Extend the environmental ingestion (weather API) to capture **temperature** and **humidity**, emit them as `.environment` events, and mine them as exposures under the tier framework (**contested** — plausible mechanism, mixed evidence). This is a bigger, ingestion-heavy round; the tier framework built here presents it honestly when it lands.
