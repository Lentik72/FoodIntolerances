import SwiftUI
import HealthGraphCore

/// The grid's selection rule, extracted from the Button action so the cap is a
/// testable transition instead of a closure only a mounted host could reach.
enum SeedSelection {
    /// Matches the limit `SymptomSeeds.validate` enforces on save. A grid that
    /// allowed more would let the user pick chips that are silently truncated.
    static let limit = 8

    /// Toggle `key`, bounded by `limit`.
    ///
    /// The cap bounds ADDITION only. The obvious spelling — a
    /// `guard selection.count < limit` in front of the whole body — also blocks
    /// removal, so a user who picks their eighth chip can no longer change
    /// their mind about any of them.
    ///
    /// Appended, never sorted: pick order survives to the chip row, because
    /// ChipRanker fills its leftover slots with seeds in the order given.
    static func toggled(_ key: String, in selection: [String], limit: Int = limit) -> [String] {
        var next = selection
        if let index = next.firstIndex(of: key) {
            next.remove(at: index)
            return next
        }
        guard next.count < limit else { return selection }
        next.append(key)
        return next
    }
}

/// Multi-select grid for "what brings you here?".
///
/// Its own chip view on purpose: QuickLogChip has no selected state and is
/// shared by all three capture surfaces, and the legacy onboarding's
/// `SymptomChip` is already an app-target-global name.
struct SeedSymptomGrid: View {
    /// Curated and ORDERED — deliberately not derived from
    /// `SymptomCatalog.all`, which is alphabetical.
    ///
    /// These are CATALOG DISPLAY NAMES, verified to exist. The catalog was
    /// ported from a body-map app and is region-oriented, so the everyday word
    /// is often not the entry: it has "Loose Stool" not "Diarrhea",
    /// "Indigestion" not "Heartburn", "Cognitive Fog" not "Brain Fog".
    /// `canonicalKey(for:)` is TOTAL — it derives a key for any string — so a
    /// wrong name here produces a plausible key that silently matches nothing.
    /// SeedCatalogTests guards against exactly that, which is why it iterates
    /// THESE NAMES and not the mapped keys.
    static let offeredNames: [String] = [
        "Headache", "Migraine", "Bloating", "Upper Abdominal Cramps", "Nausea",
        "Loose Stool", "Hard Stool", "Indigestion", "Fatigue", "Cognitive Fog",
        "Joint Pain", "Muscle Soreness", "Skin Rash", "Congestion",
        "Anxiety", "Dizziness",
    ]

    /// No filtering here. A filter would silently swallow a bad name and leave
    /// the guard test asserting a predicate the array was already filtered on —
    /// a tautology that cannot fail. Red-flag exclusion is asserted separately.
    static let offered: [String] = offeredNames.map {
        HealthGraphCore.SymptomCatalog.canonicalKey(for: $0)
    }

    @Binding var selection: [String]

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.offered, id: \.self) { key in
                let isSelected = selection.contains(key)
                Button {
                    selection = SeedSelection.toggled(key, in: selection)
                } label: {
                    Text(HealthGraphCore.SymptomCatalog.displayName(for: key))
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? HealthTheme.onAccent : HealthTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(isSelected ? HealthTheme.accent : HealthTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HealthTheme.cardBorder))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(HealthGraphCore.SymptomCatalog.displayName(for: key))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
