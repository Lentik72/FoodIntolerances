import Foundation
import SwiftData

/// Stores user's lab test results (cholesterol, thyroid, etc.)
@Model
class HealthTestResult: Identifiable {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID = UUID()

    // MARK: - Test Information
    @Attribute var testName: String           // "Cholesterol - LDL", "Thyroid TSH"
    @Attribute var category: String           // "Lipid Panel", "Thyroid", "Blood Sugar"
    @Attribute var value: String              // "142" (stored as string for flexibility)
    @Attribute var numericValue: Double?      // Optional numeric for comparisons
    @Attribute var unit: String?              // "mg/dL", "mIU/L"

    // MARK: - Reference Range
    @Attribute var normalRangeMin: Double?
    @Attribute var normalRangeMax: Double?
    @Attribute var normalRangeText: String?   // "< 100" or "70-100"
    @Attribute var status: String             // ResultStatus raw value

    // MARK: - Dates
    @Attribute var testDate: Date = Date()
    @Attribute var nextDueDate: Date?
    @Attribute var addedDate: Date = Date()

    // MARK: - Additional Info
    @Attribute var notes: String?
    @Attribute var labName: String?
    @Attribute var orderedBy: String?         // Doctor's name
    @Attribute var fastingRequired: Bool = false
    @Attribute var wasFasting: Bool?

    // MARK: - Initializer
    init(
        testName: String,
        category: String = "General",
        value: String,
        unit: String? = nil,
        normalRangeText: String? = nil,
        normalRangeMin: Double? = nil,
        normalRangeMax: Double? = nil,
        status: ResultStatus = .normal,
        testDate: Date = Date(),
        nextDueDate: Date? = nil,
        notes: String? = nil,
        labName: String? = nil
    ) {
        self.testName = testName
        self.category = category
        self.value = value
        self.unit = unit
        self.normalRangeText = normalRangeText
        self.normalRangeMin = normalRangeMin
        self.normalRangeMax = normalRangeMax
        self.status = status.rawValue
        self.testDate = testDate
        self.nextDueDate = nextDueDate
        self.notes = notes
        self.labName = labName

        // Try to parse numeric value
        self.numericValue = Double(value)
    }

    // MARK: - Computed Properties
    var statusEnum: ResultStatus {
        ResultStatus(rawValue: status) ?? .normal
    }

    var statusColor: String {
        statusEnum.colorName
    }

    var statusIcon: String {
        statusEnum.icon
    }

    var isOverdue: Bool {
        guard let dueDate = nextDueDate else { return false }
        return Date() > dueDate
    }

    var daysUntilDue: Int? {
        guard let dueDate = nextDueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day
    }

    var formattedValue: String {
        if let unit = unit {
            return "\(value) \(unit)"
        }
        return value
    }

    /// Calculate status based on numeric value and normal range
    func calculateStatus() -> ResultStatus {
        guard let numeric = numericValue else { return .normal }

        // Check against range
        if let min = normalRangeMin, let max = normalRangeMax {
            if numeric < min {
                return .low
            } else if numeric > max {
                let percentOver = ((numeric - max) / max) * 100
                return percentOver > 20 ? .high : .borderlineHigh
            } else {
                // Within range - check if borderline
                let range = max - min
                let percentInRange = (numeric - min) / range
                if percentInRange < 0.1 {
                    return .borderlineLow
                } else if percentInRange > 0.9 {
                    return .borderlineHigh
                }
                return .normal
            }
        }

        return .normal
    }
}

// MARK: - Supporting Enums

enum ResultStatus: String, Codable, CaseIterable {
    case normal = "Normal"
    case borderlineLow = "Borderline Low"
    case borderlineHigh = "Borderline High"
    case low = "Low"
    case high = "High"
    case critical = "Critical"

    var colorName: String {
        switch self {
        case .normal: return "green"
        case .borderlineLow, .borderlineHigh: return "yellow"
        case .low, .high: return "orange"
        case .critical: return "red"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .borderlineLow, .borderlineHigh: return "exclamationmark.circle.fill"
        case .low, .high: return "arrow.up.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var description: String {
        switch self {
        case .normal: return "Within normal range"
        case .borderlineLow: return "Slightly below normal"
        case .borderlineHigh: return "Slightly above normal"
        case .low: return "Below normal range"
        case .high: return "Above normal range"
        case .critical: return "Requires immediate attention"
        }
    }
}

// MARK: - Common Test Types

struct CommonHealthTest {
    let name: String
    let category: String
    let unit: String
    let normalRange: String
    let normalMin: Double?
    let normalMax: Double?
    let fastingRequired: Bool
    let frequency: String  // Recommended testing frequency

    static let all: [CommonHealthTest] = [
        // Lipid Panel
        CommonHealthTest(
            name: "Total Cholesterol",
            category: "Lipid Panel",
            unit: "mg/dL",
            normalRange: "< 200",
            normalMin: nil,
            normalMax: 200,
            fastingRequired: true,
            frequency: "Every 4-6 years (more often if at risk)"
        ),
        CommonHealthTest(
            name: "LDL Cholesterol",
            category: "Lipid Panel",
            unit: "mg/dL",
            normalRange: "< 100",
            normalMin: nil,
            normalMax: 100,
            fastingRequired: true,
            frequency: "Every 4-6 years"
        ),
        CommonHealthTest(
            name: "HDL Cholesterol",
            category: "Lipid Panel",
            unit: "mg/dL",
            normalRange: "> 40 (M) / > 50 (F)",
            normalMin: 40,
            normalMax: nil,
            fastingRequired: true,
            frequency: "Every 4-6 years"
        ),
        CommonHealthTest(
            name: "Triglycerides",
            category: "Lipid Panel",
            unit: "mg/dL",
            normalRange: "< 150",
            normalMin: nil,
            normalMax: 150,
            fastingRequired: true,
            frequency: "Every 4-6 years"
        ),

        // Blood Sugar
        CommonHealthTest(
            name: "Fasting Glucose",
            category: "Blood Sugar",
            unit: "mg/dL",
            normalRange: "70-100",
            normalMin: 70,
            normalMax: 100,
            fastingRequired: true,
            frequency: "Every 3 years after age 45"
        ),
        CommonHealthTest(
            name: "HbA1c",
            category: "Blood Sugar",
            unit: "%",
            normalRange: "< 5.7",
            normalMin: nil,
            normalMax: 5.7,
            fastingRequired: false,
            frequency: "Every 3 years (annually if prediabetic)"
        ),

        // Thyroid
        CommonHealthTest(
            name: "TSH",
            category: "Thyroid",
            unit: "mIU/L",
            normalRange: "0.4-4.0",
            normalMin: 0.4,
            normalMax: 4.0,
            fastingRequired: false,
            frequency: "Every 5 years after age 35"
        ),
        CommonHealthTest(
            name: "Free T4",
            category: "Thyroid",
            unit: "ng/dL",
            normalRange: "0.8-1.8",
            normalMin: 0.8,
            normalMax: 1.8,
            fastingRequired: false,
            frequency: "As needed based on TSH"
        ),
        CommonHealthTest(
            name: "Free T3",
            category: "Thyroid",
            unit: "pg/mL",
            normalRange: "2.3-4.2",
            normalMin: 2.3,
            normalMax: 4.2,
            fastingRequired: false,
            frequency: "As needed based on symptoms"
        ),

        // Vitamins & Minerals
        CommonHealthTest(
            name: "Vitamin D (25-OH)",
            category: "Vitamins",
            unit: "ng/mL",
            normalRange: "30-100",
            normalMin: 30,
            normalMax: 100,
            fastingRequired: false,
            frequency: "Annually if deficient"
        ),
        CommonHealthTest(
            name: "Vitamin B12",
            category: "Vitamins",
            unit: "pg/mL",
            normalRange: "200-900",
            normalMin: 200,
            normalMax: 900,
            fastingRequired: false,
            frequency: "Every 2 years after age 50"
        ),
        CommonHealthTest(
            name: "Ferritin",
            category: "Iron Studies",
            unit: "ng/mL",
            normalRange: "20-200 (M) / 10-150 (F)",
            normalMin: 20,
            normalMax: 200,
            fastingRequired: false,
            frequency: "As needed based on symptoms"
        ),
        CommonHealthTest(
            name: "Iron",
            category: "Iron Studies",
            unit: "mcg/dL",
            normalRange: "60-170",
            normalMin: 60,
            normalMax: 170,
            fastingRequired: true,
            frequency: "As needed"
        ),

        // Blood Count
        CommonHealthTest(
            name: "Hemoglobin",
            category: "Complete Blood Count",
            unit: "g/dL",
            normalRange: "12-16 (F) / 14-18 (M)",
            normalMin: 12,
            normalMax: 18,
            fastingRequired: false,
            frequency: "As needed"
        ),
        CommonHealthTest(
            name: "White Blood Cells",
            category: "Complete Blood Count",
            unit: "cells/mcL",
            normalRange: "4,500-11,000",
            normalMin: 4500,
            normalMax: 11000,
            fastingRequired: false,
            frequency: "As needed"
        ),

        // Kidney Function
        CommonHealthTest(
            name: "Creatinine",
            category: "Kidney Function",
            unit: "mg/dL",
            normalRange: "0.7-1.3",
            normalMin: 0.7,
            normalMax: 1.3,
            fastingRequired: false,
            frequency: "Annually if at risk"
        ),
        CommonHealthTest(
            name: "BUN",
            category: "Kidney Function",
            unit: "mg/dL",
            normalRange: "7-20",
            normalMin: 7,
            normalMax: 20,
            fastingRequired: false,
            frequency: "Annually if at risk"
        ),

        // Liver Function
        CommonHealthTest(
            name: "ALT",
            category: "Liver Function",
            unit: "U/L",
            normalRange: "7-56",
            normalMin: 7,
            normalMax: 56,
            fastingRequired: false,
            frequency: "As needed"
        ),
        CommonHealthTest(
            name: "AST",
            category: "Liver Function",
            unit: "U/L",
            normalRange: "10-40",
            normalMin: 10,
            normalMax: 40,
            fastingRequired: false,
            frequency: "As needed"
        ),

        // Blood Pressure (technically not a "test" but often tracked)
        CommonHealthTest(
            name: "Blood Pressure - Systolic",
            category: "Cardiovascular",
            unit: "mmHg",
            normalRange: "< 120",
            normalMin: nil,
            normalMax: 120,
            fastingRequired: false,
            frequency: "At every doctor visit"
        ),
        CommonHealthTest(
            name: "Blood Pressure - Diastolic",
            category: "Cardiovascular",
            unit: "mmHg",
            normalRange: "< 80",
            normalMin: nil,
            normalMax: 80,
            fastingRequired: false,
            frequency: "At every doctor visit"
        )
    ]

    static func find(byName name: String) -> CommonHealthTest? {
        all.first { $0.name.lowercased().contains(name.lowercased()) }
    }

    static func byCategory() -> [String: [CommonHealthTest]] {
        Dictionary(grouping: all, by: { $0.category })
    }
}
