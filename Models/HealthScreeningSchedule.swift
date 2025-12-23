import Foundation
import SwiftData

/// Tracks when health screenings are due based on user's age, gender, and conditions
@Model
class HealthScreeningSchedule: Identifiable {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID = UUID()

    // MARK: - Screening Information
    @Attribute var screeningName: String      // "Cholesterol Test", "Mammogram"
    @Attribute var screeningType: String      // ScreeningType raw value
    @Attribute var frequencyMonths: Int       // How often (in months)
    @Attribute var frequencyDescription: String  // "Every 5 years", "Annually"

    // MARK: - Eligibility
    @Attribute var minimumAge: Int?
    @Attribute var maximumAge: Int?
    @Attribute var applicableGender: String?   // "Male", "Female", nil for all
    @Attribute var relevantConditionsData: Data = Data()
    var relevantConditions: [String] {
        get {
            guard !relevantConditionsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: relevantConditionsData)) ?? []
        }
        set {
            relevantConditionsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Tracking
    @Attribute var lastCompletedDate: Date?
    @Attribute var nextDueDate: Date?
    @Attribute var reminderDate: Date?        // When to remind user
    @Attribute var isEnabled: Bool = true     // User can disable reminders
    @Attribute var timesCompleted: Int = 0
    @Attribute var notes: String?

    // MARK: - Status
    @Attribute var status: String = "pending"  // ScreeningStatus raw value

    // MARK: - Timestamps
    @Attribute var createdDate: Date = Date()
    @Attribute var lastUpdated: Date = Date()

    // MARK: - Initializer
    init(
        screeningName: String,
        screeningType: ScreeningType = .labTest,
        frequencyMonths: Int,
        frequencyDescription: String,
        minimumAge: Int? = nil,
        maximumAge: Int? = nil,
        applicableGender: String? = nil,
        relevantConditions: [String] = []
    ) {
        self.screeningName = screeningName
        self.screeningType = screeningType.rawValue
        self.frequencyMonths = frequencyMonths
        self.frequencyDescription = frequencyDescription
        self.minimumAge = minimumAge
        self.maximumAge = maximumAge
        self.applicableGender = applicableGender
        self.relevantConditions = relevantConditions
    }

    // MARK: - Computed Properties
    var screeningTypeEnum: ScreeningType {
        ScreeningType(rawValue: screeningType) ?? .labTest
    }

    var statusEnum: ScreeningStatus {
        ScreeningStatus(rawValue: status) ?? .pending
    }

    var isOverdue: Bool {
        guard let dueDate = nextDueDate else { return false }
        return Date() > dueDate
    }

    var daysUntilDue: Int? {
        guard let dueDate = nextDueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day
    }

    var isUpcoming: Bool {
        guard let days = daysUntilDue else { return false }
        return days >= 0 && days <= 30
    }

    // MARK: - Methods

    /// Check if this screening applies to a user
    func appliesTo(age: Int?, gender: String?, conditions: [String]) -> Bool {
        // Check age
        if let minAge = minimumAge, let userAge = age, userAge < minAge {
            return false
        }
        if let maxAge = maximumAge, let userAge = age, userAge > maxAge {
            return false
        }

        // Check gender
        if let requiredGender = applicableGender, let userGender = gender {
            if requiredGender != userGender {
                return false
            }
        }

        // If screening has condition requirements, check if user has any
        if !relevantConditions.isEmpty {
            let hasRelevantCondition = relevantConditions.contains { condition in
                conditions.contains { $0.lowercased().contains(condition.lowercased()) }
            }
            // Return true if user has a relevant condition OR if it's a general screening
            return hasRelevantCondition
        }

        return true
    }

    /// Mark screening as completed
    func markCompleted(date: Date = Date()) {
        lastCompletedDate = date
        timesCompleted += 1

        // Calculate next due date
        nextDueDate = Calendar.current.date(byAdding: .month, value: frequencyMonths, to: date)

        // Set reminder for 2 weeks before due
        if let dueDate = nextDueDate {
            reminderDate = Calendar.current.date(byAdding: .day, value: -14, to: dueDate)
        }

        status = ScreeningStatus.completed.rawValue
        lastUpdated = Date()
    }

    /// Calculate and set next due date based on last completion or current date
    func calculateNextDueDate() {
        if let lastDate = lastCompletedDate {
            nextDueDate = Calendar.current.date(byAdding: .month, value: frequencyMonths, to: lastDate)
        } else {
            // If never done, due now
            nextDueDate = Date()
        }

        updateStatus()
    }

    /// Update status based on dates
    func updateStatus() {
        guard let dueDate = nextDueDate else {
            status = ScreeningStatus.pending.rawValue
            return
        }

        let now = Date()
        if now > dueDate {
            status = ScreeningStatus.overdue.rawValue
        } else if let days = daysUntilDue, days <= 30 {
            status = ScreeningStatus.upcoming.rawValue
        } else {
            status = ScreeningStatus.scheduled.rawValue
        }
    }
}

// MARK: - Supporting Enums

enum ScreeningType: String, Codable, CaseIterable {
    case labTest = "Lab Test"
    case imaging = "Imaging"
    case physical = "Physical Exam"
    case procedure = "Procedure"
    case selfExam = "Self-Exam"

    var icon: String {
        switch self {
        case .labTest: return "testtube.2"
        case .imaging: return "waveform.path.ecg.rectangle"
        case .physical: return "stethoscope"
        case .procedure: return "cross.case.fill"
        case .selfExam: return "hand.raised.fill"
        }
    }
}

enum ScreeningStatus: String, Codable, CaseIterable {
    case pending = "Pending"       // Never done, not yet due
    case scheduled = "Scheduled"   // Done before, next date set
    case upcoming = "Upcoming"     // Due within 30 days
    case overdue = "Overdue"       // Past due date
    case completed = "Completed"   // Just marked as done

    var colorName: String {
        switch self {
        case .pending: return "gray"
        case .scheduled: return "blue"
        case .upcoming: return "yellow"
        case .overdue: return "red"
        case .completed: return "green"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .scheduled: return "calendar"
        case .upcoming: return "calendar.badge.exclamationmark"
        case .overdue: return "exclamationmark.triangle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Default Screenings Database

struct DefaultHealthScreenings {
    /// Get recommended screenings based on user profile
    static func getRecommendedScreenings(age: Int?, gender: String?, conditions: [String]) -> [HealthScreeningSchedule] {
        var screenings: [HealthScreeningSchedule] = []

        // General screenings for everyone
        screenings.append(HealthScreeningSchedule(
            screeningName: "Blood Pressure Check",
            screeningType: .physical,
            frequencyMonths: 12,
            frequencyDescription: "Annually",
            minimumAge: 18
        ))

        // Cholesterol - starts at 20, more frequent after 35 or with conditions
        let cholesterolAge = conditions.contains(where: { $0.contains("Heart") || $0.contains("Diabetes") }) ? 20 : 35
        screenings.append(HealthScreeningSchedule(
            screeningName: "Cholesterol/Lipid Panel",
            screeningType: .labTest,
            frequencyMonths: 60, // Every 5 years
            frequencyDescription: "Every 5 years",
            minimumAge: cholesterolAge,
            relevantConditions: ["Heart Disease", "Diabetes", "High Blood Pressure", "Obesity"]
        ))

        // Blood Sugar
        screenings.append(HealthScreeningSchedule(
            screeningName: "Fasting Blood Sugar/HbA1c",
            screeningType: .labTest,
            frequencyMonths: 36, // Every 3 years
            frequencyDescription: "Every 3 years",
            minimumAge: 45,
            relevantConditions: ["Diabetes", "Obesity", "Prediabetes"]
        ))

        // Thyroid
        screenings.append(HealthScreeningSchedule(
            screeningName: "Thyroid Function (TSH)",
            screeningType: .labTest,
            frequencyMonths: 60,
            frequencyDescription: "Every 5 years",
            minimumAge: 35,
            relevantConditions: ["Thyroid Issues", "Fatigue", "Weight Issues"]
        ))

        // Vitamin D - if symptoms or at risk
        screenings.append(HealthScreeningSchedule(
            screeningName: "Vitamin D Level",
            screeningType: .labTest,
            frequencyMonths: 12,
            frequencyDescription: "Annually if deficient",
            minimumAge: nil,
            relevantConditions: ["Fatigue", "Bone Pain", "Depression", "Vitamin D Deficiency"]
        ))

        // B12 - for vegetarians/vegans and 50+
        screenings.append(HealthScreeningSchedule(
            screeningName: "Vitamin B12",
            screeningType: .labTest,
            frequencyMonths: 24,
            frequencyDescription: "Every 2 years",
            minimumAge: 50,
            relevantConditions: ["Vegetarian", "Vegan", "Fatigue", "Anemia"]
        ))

        // Female-specific
        if gender == "Female" {
            screenings.append(HealthScreeningSchedule(
                screeningName: "Mammogram",
                screeningType: .imaging,
                frequencyMonths: 24,
                frequencyDescription: "Every 1-2 years",
                minimumAge: 40,
                maximumAge: 74,
                applicableGender: "Female",
                relevantConditions: ["Breast Cancer Family History"]
            ))

            screenings.append(HealthScreeningSchedule(
                screeningName: "Pap Smear/HPV Test",
                screeningType: .procedure,
                frequencyMonths: 36,
                frequencyDescription: "Every 3 years",
                minimumAge: 21,
                maximumAge: 65,
                applicableGender: "Female"
            ))

            screenings.append(HealthScreeningSchedule(
                screeningName: "Bone Density Scan (DEXA)",
                screeningType: .imaging,
                frequencyMonths: 24,
                frequencyDescription: "Every 2 years",
                minimumAge: 65,
                applicableGender: "Female",
                relevantConditions: ["Osteoporosis", "Menopause"]
            ))
        }

        // Male-specific
        if gender == "Male" {
            screenings.append(HealthScreeningSchedule(
                screeningName: "Prostate Exam (PSA)",
                screeningType: .labTest,
                frequencyMonths: 12,
                frequencyDescription: "Annually",
                minimumAge: 50,
                applicableGender: "Male",
                relevantConditions: ["Prostate Cancer Family History"]
            ))
        }

        // Colonoscopy - for 45+
        screenings.append(HealthScreeningSchedule(
            screeningName: "Colonoscopy",
            screeningType: .procedure,
            frequencyMonths: 120, // Every 10 years
            frequencyDescription: "Every 10 years",
            minimumAge: 45,
            maximumAge: 75,
            relevantConditions: ["Colon Cancer Family History", "Inflammatory Bowel Disease"]
        ))

        // Skin check - for everyone
        screenings.append(HealthScreeningSchedule(
            screeningName: "Skin Cancer Screening",
            screeningType: .physical,
            frequencyMonths: 12,
            frequencyDescription: "Annually",
            minimumAge: 30,
            relevantConditions: ["Skin Cancer Family History", "Fair Skin", "Sun Exposure"]
        ))

        // Eye exam
        screenings.append(HealthScreeningSchedule(
            screeningName: "Eye Exam",
            screeningType: .physical,
            frequencyMonths: 24,
            frequencyDescription: "Every 2 years",
            minimumAge: 40,
            relevantConditions: ["Diabetes", "High Blood Pressure", "Glaucoma Family History"]
        ))

        // Dental
        screenings.append(HealthScreeningSchedule(
            screeningName: "Dental Checkup",
            screeningType: .physical,
            frequencyMonths: 6,
            frequencyDescription: "Every 6 months"
        ))

        // Filter by applicability
        return screenings.filter { screening in
            screening.appliesTo(age: age, gender: gender, conditions: conditions)
        }
    }

    /// Get all default screenings (unfiltered)
    static var allScreenings: [HealthScreeningSchedule] {
        getRecommendedScreenings(age: nil, gender: nil, conditions: [])
    }
}

// MARK: - Clinical Escalation Rules

struct ClinicalEscalationRule {
    let symptom: String
    let threshold: Int          // Number of occurrences
    let timeWindowDays: Int     // Within how many days
    let minimumSeverity: Int    // Minimum severity level (1-5)
    let message: String
    let urgency: EscalationUrgency

    enum EscalationUrgency: String {
        case informational = "Informational"
        case recommended = "Recommended"
        case important = "Important"
        case urgent = "Urgent"

        var colorName: String {
            switch self {
            case .informational: return "blue"
            case .recommended: return "yellow"
            case .important: return "orange"
            case .urgent: return "red"
            }
        }
    }

    static let defaultRules: [ClinicalEscalationRule] = [
        // Headaches
        ClinicalEscalationRule(
            symptom: "Headache",
            threshold: 8,
            timeWindowDays: 30,
            minimumSeverity: 3,
            message: "You've logged 8+ headaches this month. This doesn't necessarily mean something is wrong, but frequent headaches are often worth discussing with a doctor who can help identify causes and solutions.",
            urgency: .recommended
        ),

        // Severe symptoms
        ClinicalEscalationRule(
            symptom: "Any",
            threshold: 3,
            timeWindowDays: 14,
            minimumSeverity: 5,
            message: "You've experienced several intense symptoms recently. While there may be simple explanations, patterns like this are usually worth running by a healthcare provider to rule out underlying causes.",
            urgency: .important
        ),

        // Persistent symptoms
        ClinicalEscalationRule(
            symptom: "Any",
            threshold: 14,
            timeWindowDays: 21,
            minimumSeverity: 2,
            message: "This symptom has persisted for over 2 weeks. Persistent symptoms can have many causes - a quick check-in with your doctor could help identify what's going on and find relief faster.",
            urgency: .recommended
        ),

        // Chest pain (always urgent)
        ClinicalEscalationRule(
            symptom: "Chest Pain",
            threshold: 1,
            timeWindowDays: 7,
            minimumSeverity: 3,
            message: "Chest pain has many causes (muscle strain, acid reflux, anxiety), but it's one symptom that's always worth getting checked promptly. Please consider contacting a healthcare provider.",
            urgency: .urgent
        ),

        // Breathing difficulties
        ClinicalEscalationRule(
            symptom: "Breathing",
            threshold: 2,
            timeWindowDays: 7,
            minimumSeverity: 3,
            message: "Breathing difficulties can stem from many things including allergies, anxiety, or deconditioning. Since you've logged this a few times, it may be helpful to discuss with your doctor.",
            urgency: .important
        ),

        // Digestive issues
        ClinicalEscalationRule(
            symptom: "Digestive",
            threshold: 10,
            timeWindowDays: 30,
            minimumSeverity: 2,
            message: "Frequent digestive issues are very common and often manageable, but ongoing symptoms could benefit from evaluation. A doctor or dietitian can help identify triggers and solutions.",
            urgency: .recommended
        ),

        // Sleep issues
        ClinicalEscalationRule(
            symptom: "Sleep",
            threshold: 14,
            timeWindowDays: 21,
            minimumSeverity: 3,
            message: "Sleep difficulties over time can affect overall wellbeing. If lifestyle changes haven't helped, a healthcare provider can offer additional strategies or check for underlying causes.",
            urgency: .recommended
        ),

        // Mood/Mental Health
        ClinicalEscalationRule(
            symptom: "Mood",
            threshold: 7,
            timeWindowDays: 14,
            minimumSeverity: 3,
            message: "Your recent logs suggest you've been going through a difficult stretch. Talking to someone - whether a counselor, therapist, or your doctor - can provide support and helpful perspectives.",
            urgency: .recommended
        )
    ]

    /// Check if a rule is triggered based on symptom logs
    func isTriggered(occurrences: Int, maxSeverity: Int, daysSpanned: Int) -> Bool {
        return occurrences >= threshold &&
               maxSeverity >= minimumSeverity &&
               daysSpanned <= timeWindowDays
    }
}
