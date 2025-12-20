import SwiftUI
import SwiftData

// This file helps configure SwiftData and handle common issues
extension ModelContainer {
    static var previewContainer: ModelContainer {
        let schema = Schema([
            LogEntry.self,
            TrackedItem.self,
            TherapyProtocol.self,
            TherapyProtocolItem.self,
            CabinetItem.self,
            AvoidedItem.self,
            OngoingSymptom.self,
            SymptomCheckIn.self,
            MoodEntry.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create preview container: \(error.localizedDescription)")
        }
    }
}
