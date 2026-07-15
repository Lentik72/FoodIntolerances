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
        guard let recent = try? await store.eventsPage(before: nil, limit: 300, categories: [.food], sources: [.manual]) else { return }
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
                                QuickLogChip(label: food, accessibilityLabel: "Log \(food)") {
                                    // chip tap logs immediately
                                    Task { if let e = await model.log(name: food, at: timestamp) { onLogged(e) } }
                                }
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
