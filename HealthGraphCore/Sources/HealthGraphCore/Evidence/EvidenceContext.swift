import Foundation

/// One load + one `extract` of the whole corpus, reused across many relationships.
///
/// Exists because `evidence(for:asOf:)` re-reads the entire event table and
/// re-runs all ten exposure sources to answer about a SINGLE edge — so asking
/// about N edges costs N full-corpus scans. Everything here is shared work;
/// the per-edge work stays in `evidence(for:in:)`.
struct EvidenceContext {
    let exposures: [ExposureKey: [ExposureOccurrence]]
    let outcomes: [OutcomeKey: [OutcomeOccurrence]]
    /// Hoistable. The per-target `others` map is NOT hoistable — see `evidence(for:in:)`.
    let daySets: [ExposureKey: Set<Date>]
    let illness: Set<Date>
    /// nil when the corpus is empty; every per-edge answer is then empty.
    let observation: DateInterval?
}

extension EvidenceEngine {
    /// Builds the shared context. MUST be given the same unbounded corpus
    /// `recompute()` uses: TemperatureExposureSource/HumidityExposureSource are
    /// corpus-relative (quartiles over the slice, 20-reading floor), so a
    /// narrowed read silently changes or deletes those exposures and the batch
    /// numbers stop matching the stored evidenceCount.
    func makeContext(_ events: [HealthEvent]) -> EvidenceContext {
        let cal = Self.utc
        let (exposures, outcomes) = extract(events)
        var daySets: [ExposureKey: Set<Date>] = [:]
        for (key, occ) in exposures { daySets[key] = Set(occ.map { cal.startOfDay(for: $0.timestamp) }) }
        let times = events.map(\.timestamp)
        let observation: DateInterval?
        if let lo = times.min(), let hi = times.max() { observation = DateInterval(start: lo, end: hi) }
        else { observation = nil }
        return EvidenceContext(exposures: exposures, outcomes: outcomes, daySets: daySets,
                               illness: illnessDays(events), observation: observation)
    }

    /// The per-edge half. Pure and synchronous — no I/O.
    ///
    /// Fails soft in six places, each returning the zeroed value rather than nil
    /// or a throw: unparseable edgeKey, exposure key absent, outcome key absent,
    /// empty exposures, no observation window, analyzer returns nil. Callers
    /// (InsightsViewModel) render "card with no dots" from that; dropping the
    /// entry instead would change the UI to "missing data".
    func evidence(for relationship: Relationship, in ctx: EvidenceContext) -> RelationshipEvidence {
        func empty() -> RelationshipEvidence {
            RelationshipEvidence(relationshipID: relationship.id, exposures: [],
                                 followCount: 0, missCount: 0, confounders: [])
        }
        guard let (expKey, outKey) = EdgeIdentity.parse(relationship) else { return empty() }
        guard let exp = ctx.exposures[expKey], let out = ctx.outcomes[outKey], !exp.isEmpty else { return empty() }
        guard let observation = ctx.observation else { return empty() }
        let window = config.lagWindow(for: expKey)
        guard let stats = CooccurrenceAnalyzer(config: config)
            .analyze(exposure: exp, outcome: out, window: window, observation: observation) else { return empty() }

        // Rebuilt PER TARGET: dropping the `!= expKey` filter makes every edge
        // confound itself (overlap 1.0 → maximum penalty). Only daySets is shared.
        var others = ctx.daySets.filter { $0.key != expKey }
        if !ctx.illness.isEmpty { others[Self.illnessConfounderKey] = ctx.illness }
        let (_, confounders) = ConfounderAnalyzer().penalty(targetDays: ctx.daySets[expKey] ?? [], others: others)

        return RelationshipEvidence(relationshipID: relationship.id, exposures: stats.pairs,
                                    followCount: stats.followCount, missCount: stats.missCount,
                                    confounders: confounders)
    }
}
