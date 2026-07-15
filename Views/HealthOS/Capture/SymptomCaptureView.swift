import SwiftUI
import HealthGraphCore

@MainActor
final class SymptomCaptureModel: ObservableObject {
    @Published var chipKeys: [String] = []
    @Published var pendingKey: String?          // a chip tapped, awaiting a severity tap
    @Published var searchText: String = ""
    @Published var selectedNewKey: String?      // a searched/typed symptom for the full form
    @Published var severity: Double = 5
    @Published var note: String = ""

    private let store: GRDBEventStore
    private let capture: CaptureService
    private let now: () -> Date

    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        self.store = GRDBEventStore(database: database)
        self.capture = CaptureService(database: database)
        self.now = now
    }

    // Qualified explicitly: the app target also has a legacy (pre-pivot) `SymptomCatalog` /
    // `SymptomDefinition` type at its root, which would otherwise shadow HealthGraphCore's.
    var results: [HealthGraphCore.SymptomDefinition] { HealthGraphCore.SymptomCatalog.search(searchText) }

    func loadChips() async {
        guard let recent = try? await store.eventsPage(before: nil, limit: 300, categories: [.symptom], sources: [.manual]) else { return }
        chipKeys = ChipRanker.rank(history: recent, category: .symptom, now: now(),
                                   timeZone: .current, limit: 8)
    }

    /// Canonical key for the full-form (new/searched) path — a picked result or typed text.
    func newKey() -> String? {
        if let selectedNewKey { return selectedNewKey }
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : HealthGraphCore.SymptomCatalog.canonicalKey(for: t)
    }

    @discardableResult
    func log(key: String, severity: Int?, note: String?, at timestamp: Date) async -> HealthEvent? {
        do { return try await capture.logSymptom(canonicalKey: key, severity: severity, at: timestamp, note: note) }
        catch { return nil }
    }
}

struct SymptomCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = SymptomCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let key = model.pendingKey {
                    severityStep(for: key)          // chip tapped → quick 1-tap severity
                } else {
                    if !model.chipKeys.isEmpty { chipRow }
                    searchField
                    if !model.results.isEmpty { resultList }
                    if model.newKey() != nil { newSymptomForm }   // full form for a new symptom
                }
            }
            .padding(16)
        }
        .task { await model.loadChips() }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.chipKeys, id: \.self) { key in
                    QuickLogChip(label: HealthGraphCore.SymptomCatalog.displayName(for: key)) {
                        model.pendingKey = key
                    }
                }
            }
        }
    }

    private func severityStep(for key: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How bad is \(HealthGraphCore.SymptomCatalog.displayName(for: key))?")
                    .font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
                Spacer()
                Button("Cancel") { model.pendingKey = nil }
                    .font(.footnote).foregroundStyle(HealthTheme.inkMuted).frame(minHeight: 44)
            }
            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { n in
                    Button {
                        Task {
                            if let e = await model.log(key: key, severity: n, note: nil, at: timestamp) {
                                onLogged(e); model.pendingKey = nil
                            }
                        }
                    } label: {
                        Text("\(n)").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 8).fill(HealthTheme.card))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HealthTheme.severityColor(n).opacity(0.6), lineWidth: 1))
                            .foregroundStyle(HealthTheme.ink)
                    }
                    .accessibilityLabel("Severity \(n)")
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(HealthTheme.inkMuted)
            TextField("Search or add a symptom", text: $model.searchText)
                .onChange(of: model.searchText) { _, _ in model.selectedNewKey = nil }
        }
        .padding(12).hgCard()
    }

    private var resultList: some View {
        VStack(spacing: 0) {
            ForEach(model.results.prefix(6), id: \.canonicalKey) { def in
                Button {
                    model.selectedNewKey = def.canonicalKey; model.searchText = def.displayName
                } label: {
                    HStack { Text(def.displayName).foregroundStyle(HealthTheme.ink); Spacer() }
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 12).hgCard()
    }

    private var newSymptomForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Severity: \(Int(model.severity))")
                    .font(.subheadline).foregroundStyle(HealthTheme.severityColor(Int(model.severity)))
                Slider(value: $model.severity, in: 1...10, step: 1).tint(HealthTheme.severityColor(Int(model.severity)))
            }
            TextField("Note (optional)", text: $model.note, axis: .vertical).padding(12).hgCard()
            Button {
                guard let key = model.newKey() else { return }
                Task {
                    if let e = await model.log(key: key, severity: Int(model.severity),
                                               note: model.note.isEmpty ? nil : model.note, at: timestamp) {
                        onLogged(e); model.searchText = ""; model.selectedNewKey = nil; model.note = ""
                    }
                }
            } label: { Text("Log symptom").frame(maxWidth: .infinity).padding(.vertical, 12) }
                .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent).frame(minHeight: 44)
        }
    }
}
