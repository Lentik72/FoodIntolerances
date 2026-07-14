import SwiftUI
import HealthGraphCore

@MainActor
final class MealCaptureModel: ObservableObject {
    @Published var name: String = ""
    @Published var chips: [String] = []
    private let store: GRDBEventStore
    private let capture: CaptureService
    private let now: () -> Date
    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        store = GRDBEventStore(database: database); capture = CaptureService(database: database); self.now = now
    }
    func loadChips() async {
        guard let recent = try? await store.recentEvents(limit: 300) else { return }
        chips = ChipRanker.rank(history: recent, category: .food, now: now(), timeZone: .current, limit: 8)
    }
    @discardableResult
    func log(name: String, at timestamp: Date) async -> HealthEvent? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do { return try await capture.logMeal(name: trimmed, at: timestamp) } catch { return nil }
    }
}

struct MealCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = MealCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.chips, id: \.self) { food in
                                Button {            // chip tap logs immediately
                                    Task { if let e = await model.log(name: food, at: timestamp) { onLogged(e) } }
                                } label: {
                                    Text(food).font(.footnote)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(HealthTheme.card))
                                        .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                                        .foregroundStyle(HealthTheme.inkSecondary)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel("Log \(food)")
                            }
                        }
                    }
                }
                TextField("What did you eat or drink?", text: $model.name)
                    .padding(12).hgCard()
                Button {
                    Task {
                        if let e = await model.log(name: model.name, at: timestamp) { onLogged(e); model.name = "" }
                    }
                } label: { Text("Log meal").frame(maxWidth: .infinity).padding(.vertical, 12) }
                    .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                    .foregroundStyle(HealthTheme.onAccent)
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(minHeight: 44)
            }
            .padding(16)
        }
        .task { await model.loadChips() }
    }
}
