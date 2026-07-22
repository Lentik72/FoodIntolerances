import SwiftUI
import HealthGraphCore

/// The `moonphase.*` SF Symbol for a stored phase name (the factory strips emoji at
/// ingestion, so stored values are e.g. "Full Moon"). Case-insensitive, whitespace/
/// newline-trimmed; anything outside the eight canonical names → nil (the label then
/// renders text-only — fail quiet, never a wrong glyph).
func moonPhaseSymbolName(for phase: String) -> String? {
    switch phase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "new moon":        "moonphase.new.moon"
    case "waxing crescent": "moonphase.waxing.crescent"
    case "first quarter":   "moonphase.first.quarter"
    case "waxing gibbous":  "moonphase.waxing.gibbous"
    case "full moon":       "moonphase.full.moon"
    case "waning gibbous":  "moonphase.waning.gibbous"
    case "last quarter":    "moonphase.last.quarter"
    case "waning crescent": "moonphase.waning.crescent"
    default:                nil
    }
}

/// The stored phase name of a moon-phase event, or nil for anything else. The single
/// structural gate every site goes through — no view decodes metadata itself or infers
/// the phase from displayed text.
func moonPhaseName(for event: HealthEvent) -> String? {
    guard event.category == .environment, event.subtype == "moonPhase",
          let data = event.metadata,
          let meta = try? JSONDecoder().decode([String: String].self, from: data)
    else { return nil }
    return meta["phase"]
}

/// The single moon-phase presentation used at every site: the phase glyph followed by
/// the caller-provided value text (e.g. "Waxing Gibbous"). The caller applies its own
/// `.font`/`.foregroundStyle`; hierarchical rendering keeps the lit/shadow segments
/// legible at footnote size. Combined for VoiceOver so it reads the text once, icon
/// silent. An unmappable phase renders text-only.
struct MoonPhaseLabel: View {
    let value: String
    let phase: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol = moonPhaseSymbolName(for: phase) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
            Text(value)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Moon phases — all eight") {
    VStack(alignment: .leading, spacing: 10) {
        MoonPhaseLabel(value: "New Moon", phase: "New Moon")
        MoonPhaseLabel(value: "Waxing Crescent", phase: "Waxing Crescent")
        MoonPhaseLabel(value: "First Quarter", phase: "First Quarter")
        MoonPhaseLabel(value: "Waxing Gibbous", phase: "Waxing Gibbous")
        MoonPhaseLabel(value: "Full Moon", phase: "Full Moon")
        MoonPhaseLabel(value: "Waning Gibbous", phase: "Waning Gibbous")
        MoonPhaseLabel(value: "Last Quarter", phase: "Last Quarter")
        MoonPhaseLabel(value: "Waning Crescent", phase: "Waning Crescent")
        MoonPhaseLabel(value: "Unmappable", phase: "Blood Moon")
    }
    .font(.footnote)
    .padding()
    .background(HealthTheme.paper)
}
