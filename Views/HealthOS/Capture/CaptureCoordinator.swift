import Foundation

/// Bridges a capture write (in the sheet presented from the root) to the
/// keep-alive tabs, which can't otherwise observe it. Tabs refresh on change.
@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var lastCaptureAt: Date?
    func saveCompleted() { lastCaptureAt = Date() }
}
