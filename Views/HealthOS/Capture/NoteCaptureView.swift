import SwiftUI
import HealthGraphCore

@MainActor
final class NoteCaptureModel: ObservableObject {
    @Published var text: String = ""
    private let capture: CaptureService
    init(database: AppDatabase) { capture = CaptureService(database: database) }
    @discardableResult
    func log(text: String, at timestamp: Date) async -> HealthEvent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do { return try await capture.logNote(text: trimmed, at: timestamp) } catch { return nil }
    }
}

struct NoteCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = NoteCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Write a note", text: $model.text, axis: .vertical)
                .lineLimit(3...8).padding(12).hgCard()
            Button {
                Task { if let e = await model.log(text: model.text, at: timestamp) { onLogged(e); model.text = "" } }
            } label: { Text("Save note").frame(maxWidth: .infinity).padding(.vertical, 12) }
                .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .disabled(model.text.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(16)
    }
}
