import SwiftUI

/// Calm-clinical design tokens (frozen 2026-07-07; validated against both
/// surfaces — see plan doc "Design tokens"). Every color in HealthOS views
/// comes from here or CategoryStyle. Never use ad-hoc colors in views.
enum HealthTheme {
    // MARK: surfaces & ink
    static let paper       = dyn(light: 0xFAF7F2, dark: 0x15140F)
    static let card        = dyn(light: 0xFFFFFF, dark: 0x201E17)
    static let cardBorder  = dyn(light: 0xE5DFD4, dark: 0x35322A)
    static let ink         = dyn(light: 0x1C1B18, dark: 0xEDE9E0)
    static let inkSecondary = dyn(light: 0x6B6759, dark: 0xA8A296)
    static let inkMuted    = dyn(light: 0x8F8A7B, dark: 0x7A756A)
    static let accent      = dyn(light: 0x2E7D74, dark: 0x4FA599)
    // Mood faces (starting values — tunable live in MoodFace previews)
    static let moodRough = dyn(light: 0xC46A72, dark: 0xD08A90)   // muted rose
    static let moodOkay  = dyn(light: 0x8F8A7B, dark: 0x9A9488)   // warm neutral
    static let moodGood  = dyn(light: 0x2E7D74, dark: 0x4FA599)   // sage (matches accent)
    /// Evidence dots & warm alerts ONLY (Phase 2 insight cards). Never a category color.
    static let amber       = dyn(light: 0xC77E32, dark: 0xD89A55)
    static let dotMiss     = dyn(light: 0xD8D2C6, dark: 0x4A463C)
    /// Content drawn on top of the accent fill (buttons, the capture [+]).
    static let onAccent = dyn(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Urgent/emergency action fill — the red-flag "Call 911" primary. Reuses the
    /// severe-severity terracotta for palette consistency. Emergencies ONLY.
    static let danger   = dyn(light: 0xC0442E, dark: 0xD65C44)
    static let onDanger = dyn(light: 0xFFFFFF, dark: 0xFFFFFF)

    /// EPA AirNow AQI category colors, **accessibility-adjusted** for legibility on
    /// the cream/dark surfaces (NOT verbatim official hex — pure AirNow yellow is
    /// invisible on cream, maroon is lightened for dark). Ref: airnow.gov/aqi/aqi-basics.
    /// Rendered as a small dot beside the always-present AQI number + category text.
    static let aqiGood               = dyn(light: 0x2E9E4F, dark: 0x3FD06B)   // green
    static let aqiModerate           = dyn(light: 0xB08A00, dark: 0xE8C33A)   // yellow → readable gold (light ≥3:1 on paper)
    static let aqiUnhealthySensitive = dyn(light: 0xD96500, dark: 0xFF9A3D)   // orange (light ≥3:1 on paper)
    static let aqiUnhealthy          = dyn(light: 0xD42A2A, dark: 0xFF5C5C)   // red
    static let aqiVeryUnhealthy      = dyn(light: 0x8F3F97, dark: 0xB667BE)   // purple
    static let aqiHazardous          = dyn(light: 0x7E0023, dark: 0xC64B6B)   // maroon

    // MARK: type — semantic styles only, so Dynamic Type scales everything
    static func screenTitle() -> Font { .system(.largeTitle, design: .serif, weight: .semibold) }
    static func sectionHeader() -> Font { .system(.title3, design: .serif, weight: .semibold) }

    /// Calm 3-band severity ramp for symptom severity 1–10. Stays in the warm
    /// clinical palette: mild → sage, moderate → amber, severe → terracotta.
    static func severityColor(_ severity: Int) -> Color {
        switch severity {
        case ..<4:  return dyn(light: 0x5E8C5A, dark: 0x7CA877)   // 1–3 mild — sage green
        case 4...6: return dyn(light: 0xE0A21E, dark: 0xE8B23E)   // 4–6 moderate — golden amber
        default:    return dyn(light: 0xC0442E, dark: 0xD65C44)   // 7–10 severe — terracotta
        }
    }

    // MARK: shape
    static let cardCornerRadius: CGFloat = 12

    // MARK: helpers
    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// Standard calm-clinical card: white/warm-dark surface, hairline border,
    /// 12pt radius, faint shadow.
    func hgCard() -> some View {
        self
            .background(HealthTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(HealthTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}
