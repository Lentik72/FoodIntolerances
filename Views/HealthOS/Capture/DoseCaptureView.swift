import SwiftUI
import HealthGraphCore

@MainActor
final class DoseCaptureModel: ObservableObject {
    @Published var kind: DoseKind = .supplement { didSet { route = ""; Task { await loadChips() } } }
    @Published var substance: String = ""
    @Published var amountText: String = ""
    @Published var unit: String = "mg"
    @Published var route: String = ""
    @Published var chips: [String] = []
    static let units = ["mg", "mcg", "iu", "ml", "tablet", "capsule", "drop", "spray"]
    private let store: GRDBEventStore
    private let capture: CaptureService
    private let now: () -> Date
    private var recent: [HealthEvent] = []
    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        store = GRDBEventStore(database: database); capture = CaptureService(database: database); self.now = now
    }
    func loadChips() async {
        recent = (try? await store.eventsPage(before: nil, limit: 300, categories: [kind.eventCategory], sources: [.manual])) ?? []
        chips = ChipRanker.rank(history: recent, category: kind.eventCategory, now: now(), timeZone: .current, limit: 8)
    }
    private func lastDose(for substance: String) -> (Double?, String?) {
        let hit = recent.first { $0.subtype == substance && [.medication, .supplement, .peptide].contains($0.category) }
        return (hit?.value, hit?.unit)
    }
    /// Chip tap: log this substance again at its last-used amount/unit.
    @discardableResult
    func logChip(substance: String, at timestamp: Date) async -> HealthEvent? {
        let (amount, u) = lastDose(for: substance)
        do { return try await capture.logDose(substance: substance, kind: kind, amount: amount, unit: u, route: nil, at: timestamp) }
        catch { return nil }
    }
    /// Form: log the typed substance/amount/unit/route.
    @discardableResult
    func saveForm(at timestamp: Date) async -> HealthEvent? {
        let name = substance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
        do {
            return try await capture.logDose(substance: name, kind: kind, amount: amount,
                                             unit: amount == nil ? nil : unit,
                                             route: route.isEmpty ? nil : route, at: timestamp)
        } catch { return nil }
    }
}

struct DoseCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = DoseCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Kind", selection: $model.kind) {
                    Text("Medication").tag(DoseKind.medication)
                    Text("Supplement").tag(DoseKind.supplement)
                    Text("Peptide").tag(DoseKind.peptide)
                }.pickerStyle(.segmented)

                if !model.chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.chips, id: \.self) { s in
                                Button {            // chip tap logs at the last-used amount/unit
                                    Task { if let e = await model.logChip(substance: s, at: timestamp) { onLogged(e) } }
                                } label: {
                                    Text(s).font(.footnote).padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(HealthTheme.card))
                                        .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                                        .foregroundStyle(HealthTheme.inkSecondary)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }.accessibilityLabel("Log \(s)")
                            }
                        }
                    }
                }
                TextField("Substance name", text: $model.substance).padding(12).hgCard()
                HStack(spacing: 12) {
                    TextField("Amount", text: $model.amountText)
                        .keyboardType(.decimalPad).padding(12).hgCard()
                    Menu {
                        ForEach(DoseCaptureModel.units, id: \.self) { u in
                            Button(u) { model.unit = u }
                        }
                    } label: {
                        HStack { Text(model.unit); Image(systemName: "chevron.down").font(.footnote) }
                            .padding(12).frame(minHeight: 44).hgCard()
                    }
                }
                if model.kind != .supplement {
                    TextField("Route (e.g. subQ, oral)", text: $model.route).padding(12).hgCard()
                }
                Button {
                    Task {
                        if let e = await model.saveForm(at: timestamp) {
                            onLogged(e); model.substance = ""; model.amountText = ""; model.route = ""
                        }
                    }
                } label: { Text("Log dose").frame(maxWidth: .infinity).padding(.vertical, 12) }
                    .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                    .foregroundStyle(HealthTheme.onAccent)
                    .disabled(model.substance.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(minHeight: 44)
            }
            .padding(16)
        }
        .task { await model.loadChips() }
    }
}
