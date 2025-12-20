import SwiftUI
import SwiftData

class LogsViewModel: ObservableObject {
    @Published var startDate: Date = Date(timeIntervalSince1970: 0)
    @Published var endDate: Date = Date(timeIntervalSinceNow: 60*60*24*365*5)
    @Published var minSeverity: Int = 1
    @Published var selectedCategory: String = "All"
    @Published var availableCategories: [String] = ["All"]
    @Published var showActiveOnly: Bool = true
    @Published var showResolvedOnly: Bool = false
    @Published var selectedSymptoms: Set<String> = []
    @Published var selectedFoods: Set<String> = []
    @Published var selectedMoonPhases: Set<String> = []
    @Published var hasSuddenPressureChange: Bool = false
    @Published var selectedMercuryStatus: Set<String> = []
    @Published var selectedAtmosphericPressureCategories: Set<String> = []
    @Published var allAtmosphericPressureCategories: [String] = ["Low", "Normal", "High"]
    @Published var allSymptoms: [String] = ["Headache", "Nausea", "Fatigue", "Abdominal Pain", "Dizziness"]
    @Published var allFoods: [String] = []
    @Published var allMoonPhases: [String] = []
    @Published var allMercuryStatuses: [String] = ["In Retrograde", "Direct"]
    
    private func getUniqueCategories(from logs: [LogEntry]) -> [String] {
        let categories = logs.map { $0.category }
        return ["All"] + Array(Set(categories)).sorted()
    }
}

