import SwiftUI
import HealthGraphCore

/// Settings: per-symptom toggles for the seek-care reminders. ON = you'll be
/// reminded; OFF = muted. Full list so the feature is discoverable and re-enabling
/// is one tap.
struct RedFlagRemindersView: View {
    @EnvironmentObject private var muteStore: RedFlagMuteStore

    // Qualified: the app target has a legacy `SymptomCatalog` that would otherwise shadow this.
    private func name(_ key: String) -> String { HealthGraphCore.SymptomCatalog.displayName(for: key) }
    private var keys: [String] {
        RedFlagCatalog.mutableSymptomKeys.sorted {
            name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(keys, id: \.self) { key in
                    Toggle(name(key), isOn: Binding(
                        get: { !muteStore.isMuted(key) },
                        set: { on in on ? muteStore.unmute(key) : muteStore.mute(key) }
                    ))
                }
            } header: {
                Text("When you log one of these symptoms, the app reminds you to consider urgent care. These aren't diagnoses. Turn any off if the reminder isn't useful for you — you can turn it back on here anytime.")
            }
        }
        .navigationTitle("Safety reminders")
    }
}

#Preview {
    NavigationStack { RedFlagRemindersView().environmentObject(RedFlagMuteStore()) }
}
