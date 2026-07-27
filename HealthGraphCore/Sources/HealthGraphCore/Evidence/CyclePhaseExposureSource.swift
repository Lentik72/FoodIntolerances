import Foundation

/// Cycle-phase exposures. v1 scopes to the two symptomatic windows: menstrual
/// (a period-start day) and luteal (the configured number of days before the
/// *next* start). Each phase-day is emitted as one occurrence at that day's
/// start, so the analyzer treats it with a standard 24h window.
///
/// Start resolution is authority-first. HealthKit stamps
/// `HKMetadataKeyMenstrualCycleStart` on flow samples; that marker is
/// authoritative and run inference is only a fallback for export/legacy rows
/// that carry no marker. Inference must never override or crowd out authority —
/// this source sees a truncated in-memory slice, so "first row in the slice" is
/// not "first day of the period".
public struct CyclePhaseExposureSource: ExposureSource {
    let config: EvidenceConfig
    let timeZone: TimeZone
    public init(config: EvidenceConfig, timeZone: TimeZone) {
        self.config = config; self.timeZone = timeZone
    }

    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let cycle = events.filter { $0.category == .cycle }

        // 1. Authoritative: explicit manual starts + marker == true.
        var authoritative = Set(cycle.filter { $0.subtype == "periodStart" }
            .map { cal.startOfDay(for: $0.timestamp) })
        let flow = cycle.filter { $0.subtype == "menstrualFlow" }
        authoritative.formUnion(flow.filter { $0.menstrualCycleStart == true }
            .map { cal.startOfDay(for: $0.timestamp) })

        // 2. Inferred candidates: run detection walks every NON-authoritative
        //    flow day — nil AND false — so a block of `false` days continues
        //    a run instead of splitting it into two (a `false` block inside
        //    one bleeding episode must not fabricate a second period start).
        //    Candidacy is still nil-only: `false` is a positive "not a start"
        //    statement and must never itself be appended to `inferred`. Within
        //    a run we track the FIRST `nil` day seen and only add it once the
        //    run ends (or the sequence does) — a run that begins with `false`
        //    days must not make the first following `nil` day look like the
        //    start of a NEW run when it is really mid-run.
        let nilDays = Set(flow.filter { $0.menstrualCycleStart == nil }
            .map { cal.startOfDay(for: $0.timestamp) })
        let runDays = Set(flow.filter { $0.menstrualCycleStart != true }
            .map { cal.startOfDay(for: $0.timestamp) }).sorted()
        var inferred: [Date] = []
        var previous: Date?
        var runCandidate: Date?   // first `nil` day seen in the current run, if any
        for d in runDays {
            var sameRun = false
            if let p = previous, let gap = cal.dateComponents([.day], from: p, to: d).day,
               gap <= config.maxFlowGapDays {
                sameRun = true
            }
            if !sameRun {
                // Run boundary: flush the previous run's candidate (if it had
                // one — a run made entirely of `false` days contributes none).
                if let candidate = runCandidate { inferred.append(candidate) }
                runCandidate = nil
            }
            if runCandidate == nil, nilDays.contains(d) {
                runCandidate = d
            }
            previous = d
        }
        if let candidate = runCandidate { inferred.append(candidate) }

        // 3. Drop inferred candidates near ANY authoritative start, either side.
        let sortedAuthoritative = authoritative.sorted()
        inferred = inferred.filter { candidate in
            !sortedAuthoritative.contains { a in
                guard let gap = cal.dateComponents([.day], from: min(a, candidate),
                                                   to: max(a, candidate)).day else { return false }
                return gap < config.minInferredStartGapDays
            }
        }

        // 4. Apply the same gap among the surviving inferred candidates.
        var keptInferred: [Date] = []
        for candidate in inferred {
            if let last = keptInferred.last,
               let gap = cal.dateComponents([.day], from: last, to: candidate).day,
               gap < config.minInferredStartGapDays { continue }
            keptInferred.append(candidate)
        }

        // 5. Union + dedupe by day.
        let starts = Array(authoritative.union(keptInferred)).sorted()
        guard !starts.isEmpty else { return [] }

        var out: [ExposureOccurrence] = []
        func occ(_ phase: CyclePhase, day: Date) -> ExposureOccurrence {
            let d = cal.startOfDay(for: day)
            // Deterministic synthetic id from the day (phase-days aren't graph events).
            let sid = UUID(uuidString: ShortSleepExposureSource.uuid(from: d)) ?? UUID()
            return ExposureOccurrence(key: .derived(.cyclePhase(phase)), timestamp: d,
                                      timezoneID: timeZone.identifier, sourceEventID: sid)
        }
        // One start is enough for its own menstrual day; a luteal window needs
        // two, because it is defined relative to the NEXT start.
        for start in starts { out.append(occ(.menstrual, day: start)) }
        guard starts.count >= 2 else { return out }
        for i in 1..<starts.count {
            let nextStart = cal.startOfDay(for: starts[i])
            if config.lutealWindowDays >= 1 {
                for back in 1...config.lutealWindowDays {
                    if let day = cal.date(byAdding: .day, value: -back, to: nextStart) {
                        out.append(occ(.luteal, day: day))
                    }
                }
            }
        }
        return out
    }
}
