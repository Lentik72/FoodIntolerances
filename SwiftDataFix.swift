import SwiftUI
import SwiftData

// Define the modifier struct first, outside of any extension
struct SwiftDataResetModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    
    func body(content: Content) -> some View {
        content
            .task {
                // Force a reload of SwiftData contexts
                do {
                    // Try fetching different entity types to ensure all are refreshed
                    let logDescriptor = FetchDescriptor<LogEntry>()
                    let trackedItemDescriptor = FetchDescriptor<TrackedItem>()
                    let protocolDescriptor = FetchDescriptor<TherapyProtocol>()
                    
                    let _ = try modelContext.fetch(logDescriptor)
                    let _ = try modelContext.fetch(trackedItemDescriptor)
                    let _ = try modelContext.fetch(protocolDescriptor)
                    
                    try modelContext.save()
                    Logger.info("SwiftData cache reset complete", category: .data)
                } catch {
                    Logger.error(error, message: "SwiftData cache reset failed", category: .data)

                    // Attempt recovery when error occurs
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        recoverFromSwiftDataError()
                    }
                }
            }
    }

    private func recoverFromSwiftDataError() {
        do {
            try modelContext.save()
            Logger.info("SwiftData recovery successful", category: .data)
        } catch {
            Logger.error(error, message: "SwiftData recovery attempt failed", category: .data)
        }
    }
}

// Then extend View to add the convenience method
extension View {
    func resetSwiftDataCache() -> some View {
        self.modifier(SwiftDataResetModifier())
    }
}
