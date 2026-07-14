import Foundation

public enum EventDisplay {
    private static let titles: [String: String] = [
        // sleep
        "inBed": "In bed", "asleepUnspecified": "Asleep", "awake": "Awake",
        "asleepCore": "Core sleep", "asleepDeep": "Deep sleep", "asleepREM": "REM sleep",
        // exercise
        "steps": "Steps", "running": "Running", "walking": "Walking", "cycling": "Cycling",
        "swimming": "Swimming", "yoga": "Yoga", "strengthTraining": "Strength training",
        "hiit": "HIIT", "hiking": "Hiking", "pilates": "Pilates", "rowing": "Rowing",
        "elliptical": "Elliptical", "stairClimbing": "Stair climbing", "dance": "Dance",
        "tennis": "Tennis", "basketball": "Basketball", "soccer": "Soccer", "golf": "Golf",
        "paddleSports": "Paddle sports", "martialArts": "Martial arts",
        "coreTraining": "Core training", "other": "Workout",
        // vitals
        "restingHeartRate": "Resting heart rate", "heartRate": "Heart rate", "hrv": "HRV",
        "respiratoryRate": "Respiratory rate",
        "bloodPressureSystolic": "Blood pressure (systolic)",
        "bloodPressureDiastolic": "Blood pressure (diastolic)",
        // bodyMetric / cycle / stress
        "weight": "Weight", "menstrualFlow": "Menstrual flow", "mindfulness": "Mindfulness",
        // food daily stats
        "dietaryEnergy": "Energy", "dietaryProtein": "Protein", "dietaryCarbs": "Carbs",
        "dietaryFat": "Fat", "dietarySugar": "Sugar", "dietarySodium": "Sodium",
        // environment
        "pressure": "Air pressure", "pressureDrop": "Pressure drop", "moonPhase": "Moon phase",
        "mercuryRetrograde": "Mercury retrograde", "season": "Season",
    ]

    public static func title(for event: HealthEvent) -> String {
        // A note's title IS its text.
        if event.category == .note, let s = event.subtype, !s.isEmpty { return s }
        guard let subtype = event.subtype, !subtype.isEmpty else {
            return event.category.rawValue.prefix(1).uppercased() + event.category.rawValue.dropFirst()
        }
        if let mapped = titles[subtype] { return mapped }
        // Unknown subtype (manual food names, HK symptom identifiers not in the map):
        // capitalize the first letter, split camelCase humps to spaces.
        var out = ""
        for (i, ch) in subtype.enumerated() {
            // `Character(ch.uppercased())` traps when a case change yields >1 grapheme
            // (e.g. "ß" → "SS"), reachable via user-typed food names in 1C — append the String.
            if i == 0 { out.append(contentsOf: ch.uppercased()) }
            else if ch.isUppercase { out.append(" "); out.append(ch) }
            else { out.append(ch) }
        }
        return out
    }

    public static func valueLine(for event: HealthEvent) -> String? {
        if event.category == .environment,
           let data = event.metadata,
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            if let phase = dict["phase"] { return phase }
            if let season = dict["season"] { return season }
        }
        guard let value = event.value else { return nil }
        switch event.unit {
        case "min": return durationString(minutes: value)
        case "severity": return "severity \(Int(value))"
        case "count":
            let grouped = Self.grouped(Int(value))
            return event.subtype == "steps" ? "\(grouped) steps" : grouped
        case "kg": return String(format: "%.1f kg", value)
        case "level":
            switch Int(value) {
            case 1: return "light"
            case 2: return "medium"
            case 3: return "heavy"
            default: return nil
            }
        case let u? where ["mg", "mcg", "iu", "ml", "tablet", "capsule", "drop", "spray"].contains(u)
                && [.medication, .supplement, .peptide].contains(event.category):
            return "\(trimmed(value)) \(u)"
        case let unit? where ["kcal", "g", "mg", "bpm", "ms", "hPa", "mmHg", "breaths/min"].contains(unit):
            return String(format: "%.0f %@", value, unit)
        case let unit?: return "\(String(format: "%g", value)) \(unit)"
        case nil: return String(format: "%g", value)
        }
    }

    /// Whole number → plain Int string ("2000"); otherwise trimmed decimal ("0.25").
    private static func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    public static func durationString(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60, m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func grouped(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        // Deterministic grouping regardless of host/simulator locale (tests assert
        // "8,214"). Locale-aware grouping is a later i18n item (see Carried forward).
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
