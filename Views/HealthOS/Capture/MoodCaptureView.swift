import SwiftUI
import HealthGraphCore

@MainActor
final class MoodCaptureModel: ObservableObject {
    @Published var note: String = ""
    private let capture: CaptureService
    init(database: AppDatabase) { self.capture = CaptureService(database: database) }
    @discardableResult
    func log(_ level: MoodLevel, at timestamp: Date, note: String?) async -> HealthEvent? {
        do { return try await capture.logMood(level: level, at: timestamp, note: note) }
        catch { return nil }
    }
}

/// Capture-sheet Mood tab: tap one of five faces (+ optional note); back-dated via the
/// sheet's shared "When" picker. The Home quick-check is the fast path; this is the
/// "with note / earlier time" path.
struct MoodCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = MoodCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(MoodLevel.allCases, id: \.rawValue) { level in
                    Button {
                        Task {
                            let note = model.note.isEmpty ? nil : model.note
                            if let e = await model.log(level, at: timestamp, note: note) {
                                onLogged(e); model.note = ""
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(level.emoji).font(.largeTitle)
                            Text(level.label).font(.caption).foregroundStyle(HealthTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64).contentShape(Rectangle())
                    }
                    .accessibilityLabel(level.label)
                }
            }
            .padding(.horizontal, 16)

            TextField("Add a note (optional)", text: $model.note, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3).padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

#Preview {
    MoodCaptureView(timestamp: .constant(Date()), onLogged: { _ in })
}
