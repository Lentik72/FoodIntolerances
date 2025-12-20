import Foundation
import SwiftData

@Model
class Symptom: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var name: String
    @Attribute var severity: Int
    @Attribute var dateLogged: Date

    init(name: String, severity: Int, dateLogged: Date) {
        self.name = name
        self.severity = severity
        self.dateLogged = dateLogged
    }
}
