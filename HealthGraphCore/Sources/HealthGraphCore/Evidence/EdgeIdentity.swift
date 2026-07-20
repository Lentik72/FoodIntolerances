import Foundation

/// Deterministic serialization of an edge's identity. `edgeKey` is the unique,
/// non-null upsert key (migration v5); the structured columns are populated for
/// indexed queries and name resolution. `parse` reverses `edgeKey` so
/// `evidence(for:)` can re-derive an edge's occurrences on demand.
public enum EdgeIdentity {
    static func fromToken(_ key: ExposureKey) -> String {
        switch key {
        case let .object(uuid, category): return "obj:\(uuid.uuidString):\(category.rawValue)"
        case let .derived(kind):
            switch kind {
            case .shortSleep: return "derived:shortSleep"
            case .highStress: return "derived:highStress"
            case .pressureDrop: return "derived:pressureDrop"
            case let .cyclePhase(phase): return "derived:cyclePhase.\(phase.rawValue)"
            case .fullMoon: return "derived:fullMoon"
            case .mercuryRetrograde: return "derived:mercuryRetrograde"
            case .hotDay: return "derived:hotDay"
            case .coldDay: return "derived:coldDay"
            case .humidDay: return "derived:humidDay"
            }
        }
    }
    static func toToken(_ key: OutcomeKey) -> String {
        switch key {
        case let .symptom(subtype): return "symptom:\(subtype)"
        case .lowMood: return "mood:low"
        case .goodMood: return "mood:good"
        }
    }

    public static func edgeKey(from: ExposureKey, to: OutcomeKey, type: RelationshipType) -> String {
        "\(fromToken(from))|\(toToken(to))|\(type.rawValue)"
    }

    public static func columns(from: ExposureKey, to: OutcomeKey)
        -> (fromObjectID: UUID?, fromCategory: String?, toCategory: String, toSubtype: String?) {
        let fromObjectID: UUID?
        let fromCategory: String?
        switch from {
        case let .object(uuid, category): fromObjectID = uuid; fromCategory = category.rawValue
        case .derived: fromObjectID = nil; fromCategory = fromToken(from).replacingOccurrences(of: "derived:", with: "")
        }
        switch to {
        case let .symptom(subtype): return (fromObjectID, fromCategory, "symptom", subtype)
        case .lowMood: return (fromObjectID, fromCategory, "mood", "low")
        case .goodMood: return (fromObjectID, fromCategory, "mood", "good")
        }
    }

    public static func parse(_ r: Relationship) -> (exposure: ExposureKey, outcome: OutcomeKey)? {
        guard let key = r.edgeKey else { return nil }
        let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        guard let exposure = parseFrom(parts[0]), let outcome = parseTo(parts[1]) else { return nil }
        return (exposure, outcome)
    }

    static func parseFrom(_ token: String) -> ExposureKey? {
        if token.hasPrefix("obj:") {
            let rest = token.dropFirst(4).split(separator: ":", maxSplits: 1).map(String.init)
            guard rest.count == 2, let uuid = UUID(uuidString: rest[0]),
                  let category = EventCategory(rawValue: rest[1]) else { return nil }
            return .object(uuid, category)
        }
        if token.hasPrefix("derived:") {
            let kind = String(token.dropFirst(8))
            switch kind {
            case "shortSleep": return .derived(.shortSleep)
            case "highStress": return .derived(.highStress)
            case "pressureDrop": return .derived(.pressureDrop)
            case "fullMoon": return .derived(.fullMoon)
            case "mercuryRetrograde": return .derived(.mercuryRetrograde)
            case "hotDay": return .derived(.hotDay)
            case "coldDay": return .derived(.coldDay)
            case "humidDay": return .derived(.humidDay)
            default:
                if kind.hasPrefix("cyclePhase."),
                   let phase = CyclePhase(rawValue: String(kind.dropFirst("cyclePhase.".count))) {
                    return .derived(.cyclePhase(phase))
                }
                return nil
            }
        }
        return nil
    }

    static func parseTo(_ token: String) -> OutcomeKey? {
        if token.hasPrefix("symptom:") { return .symptom(String(token.dropFirst(8))) }
        if token == "mood:low" { return .lowMood }
        if token == "mood:good" { return .goodMood }
        return nil
    }
}
