import Foundation
import SwiftData

@Model
class MoodEntry {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var mood: String
    @Attribute var date: Date

    init(mood: String, date: Date = Date()) {
        self.id = UUID()
        self.mood = mood
        self.date = date
    }
}
