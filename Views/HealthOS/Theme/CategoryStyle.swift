import SwiftUI
import HealthGraphCore

/// The 8 color families covering all 20 EventCategory cases.
/// Palette validated (all-pairs CVD light ΔE ≥ 14.0 / dark ≥ 13.8);
/// color NEVER appears without an icon + text label beside it.
enum CategoryFamily: String, CaseIterable, Identifiable {
    case sleep, movement, food, doses, symptoms, body, mind, context

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleep: "Sleep"
        case .movement: "Movement"
        case .food: "Food"
        case .doses: "Doses"
        case .symptoms: "Symptoms"
        case .body: "Body"
        case .mind: "Mind"
        case .context: "Context"
        }
    }

    var color: Color {
        switch self {
        case .sleep:    dyn(light: 0x3D50B5, dark: 0x5265D6)
        case .movement: dyn(light: 0x2893B4, dark: 0x27A3C9)
        case .food:     dyn(light: 0x47702F, dark: 0x4E7F2E)
        case .doses:    dyn(light: 0x7A4295, dark: 0x8C55B5)
        case .symptoms: dyn(light: 0xC6815A, dark: 0xCA8056)
        case .body:     dyn(light: 0xB04A5A, dark: 0xC36070)
        case .mind:     dyn(light: 0x904374, dark: 0xB14B8C)
        case .context:  dyn(light: 0x8A8272, dark: 0xA29B8A)
        }
    }

    var categories: Set<EventCategory> {
        switch self {
        case .sleep: [.sleep]
        case .movement: [.exercise]
        case .food: [.food]
        case .doses: [.medication, .supplement, .peptide]
        case .symptoms: [.symptom, .illness, .stool]
        case .body: [.vitals, .bodyMetric, .lab, .cycle]
        case .mind: [.mood, .stress]
        case .context: [.environment, .travel, .doctorVisit, .protocolMarker, .note]
        }
    }

    private func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: CGFloat((dark >> 16) & 0xFF) / 255, green: CGFloat((dark >> 8) & 0xFF) / 255,
                          blue: CGFloat(dark & 0xFF) / 255, alpha: 1)
                : UIColor(red: CGFloat((light >> 16) & 0xFF) / 255, green: CGFloat((light >> 8) & 0xFF) / 255,
                          blue: CGFloat(light & 0xFF) / 255, alpha: 1)
        })
    }
}

struct CategoryStyle {
    let color: Color
    let icon: String
    let family: CategoryFamily

    static func style(for category: EventCategory) -> CategoryStyle {
        let (family, icon): (CategoryFamily, String) = switch category {
        case .sleep: (.sleep, "moon.zzz.fill")
        case .exercise: (.movement, "figure.run")
        case .food: (.food, "fork.knife")
        case .medication: (.doses, "pills.fill")
        case .supplement: (.doses, "leaf.fill")
        case .peptide: (.doses, "syringe.fill")
        case .symptom: (.symptoms, "exclamationmark.circle")
        case .illness: (.symptoms, "medical.thermometer")
        case .stool: (.symptoms, "toilet.fill")
        case .vitals: (.body, "waveform.path.ecg")
        case .bodyMetric: (.body, "scalemass.fill")
        case .lab: (.body, "testtube.2")
        case .cycle: (.body, "drop.circle.fill")
        case .mood: (.mind, "face.smiling")
        case .stress: (.mind, "brain.head.profile")
        case .environment: (.context, "cloud.sun.fill")
        case .travel: (.context, "airplane")
        case .doctorVisit: (.context, "stethoscope")
        case .protocolMarker: (.context, "checklist")
        case .note: (.context, "note.text")
        }
        return CategoryStyle(color: family.color, icon: icon, family: family)
    }
}
