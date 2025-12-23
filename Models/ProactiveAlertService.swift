import Foundation
import UserNotifications
import SwiftData

/// Service for generating proactive AI-driven notifications
/// Sends alerts based on environmental conditions, health patterns, and user history
class ProactiveAlertService {

    static let shared = ProactiveAlertService()

    // MARK: - Alert Categories

    enum AlertCategory: String {
        case environmental = "environmental"
        case healthScreening = "health-screening"
        case supplementReminder = "supplement-reminder"
        case patternAlert = "pattern-alert"
        case doctorRecommendation = "doctor-recommendation"

        var identifier: String {
            "proactive-\(rawValue)"
        }
    }

    // MARK: - Environmental Alerts

    /// Check environmental conditions and send alerts if they match user's triggers
    func checkEnvironmentalConditions(
        pressure: String,
        memories: [AIMemory],
        completion: @escaping (Bool) -> Void
    ) {
        // Check if low pressure and user has pressure-sensitive triggers
        if pressure.lowercased() == "low" {
            let pressureSensitiveMemories = memories.filter { memory in
                memory.isActive &&
                memory.memoryTypeEnum == .trigger &&
                (memory.trigger?.lowercased().contains("pressure") == true ||
                 memory.symptom?.lowercased().contains("headache") == true ||
                 memory.symptom?.lowercased().contains("migraine") == true)
            }

            if !pressureSensitiveMemories.isEmpty {
                // Find what has helped before
                let remedies = memories.filter { memory in
                    memory.isActive &&
                    memory.memoryTypeEnum == .whatWorked &&
                    pressureSensitiveMemories.contains { trigger in
                        trigger.symptom == memory.symptom
                    }
                }

                var body = "Based on your history, low pressure days may trigger symptoms."
                if let topRemedy = remedies.sorted(by: { $0.effectivenessScore > $1.effectivenessScore }).first,
                   let resolution = topRemedy.resolution {
                    body += " Consider: \(resolution)"
                }

                scheduleImmediateNotification(
                    title: "Low Pressure Alert",
                    body: body,
                    category: .environmental,
                    identifier: "pressure-alert-\(Date().formatted(date: .numeric, time: .omitted))"
                )
                completion(true)
                return
            }
        }

        // Check for high pressure
        if pressure.lowercased() == "high" {
            let highPressureMemories = memories.filter { memory in
                memory.isActive &&
                memory.memoryTypeEnum == .trigger &&
                memory.trigger?.lowercased().contains("pressure") == true
            }

            if !highPressureMemories.isEmpty {
                scheduleImmediateNotification(
                    title: "High Pressure Today",
                    body: "Atmospheric pressure is elevated. Stay hydrated and monitor for symptoms.",
                    category: .environmental,
                    identifier: "pressure-high-\(Date().formatted(date: .numeric, time: .omitted))"
                )
                completion(true)
                return
            }
        }

        completion(false)
    }

    // MARK: - Health Screening Reminders

    /// Schedule reminders for upcoming and overdue health screenings
    func scheduleScreeningReminders(screenings: [HealthScreeningSchedule]) {
        // Cancel existing screening notifications
        cancelAllNotifications(withPrefix: "screening-")

        for screening in screenings where screening.isEnabled {
            // Overdue screenings - immediate alert
            if screening.isOverdue {
                let daysOverdue = abs(screening.daysUntilDue ?? 0)
                scheduleImmediateNotification(
                    title: "Health Screening Overdue",
                    body: "\(screening.screeningName) is \(daysOverdue) days overdue. Consider scheduling soon.",
                    category: .healthScreening,
                    identifier: "screening-overdue-\(screening.id.uuidString)"
                )
            }
            // Upcoming screenings - schedule reminder
            else if screening.isUpcoming, let dueDate = screening.nextDueDate {
                let daysUntil = screening.daysUntilDue ?? 0
                if daysUntil <= 7 && daysUntil > 0 {
                    // Schedule for morning of day before
                    let reminderDate = Calendar.current.date(byAdding: .day, value: -1, to: dueDate) ?? dueDate
                    scheduleNotification(
                        title: "Health Screening Coming Up",
                        body: "\(screening.screeningName) is due in \(daysUntil) days.",
                        category: .healthScreening,
                        identifier: "screening-upcoming-\(screening.id.uuidString)",
                        at: reminderDate,
                        hour: 9,
                        minute: 0
                    )
                }
            }
        }
    }

    // MARK: - Supplement Reminders Based on Patterns

    /// Send reminders for supplements that have historically helped
    func scheduleSupplementReminders(
        memories: [AIMemory],
        recentLogs: [LogEntry],
        at hour: Int = 8,
        minute: Int = 0
    ) {
        // Cancel existing supplement notifications
        cancelAllNotifications(withPrefix: "supplement-")

        // Find supplements that have worked well
        let effectiveRemedies = memories.filter { memory in
            memory.isActive &&
            memory.memoryTypeEnum == .whatWorked &&
            memory.effectivenessScore > 0.6 &&
            memory.occurrenceCount >= 3
        }

        // Check recent symptoms to see if any match
        let recentSymptoms = Set(recentLogs.prefix(10).flatMap { $0.symptoms })

        for remedy in effectiveRemedies {
            guard let symptom = remedy.symptom,
                  let resolution = remedy.resolution else { continue }

            // If user recently had this symptom, remind about the remedy
            if recentSymptoms.contains(symptom) {
                scheduleNotification(
                    title: "Wellness Reminder",
                    body: "\(resolution) has helped with \(symptom) (\(remedy.effectivenessPercentage)% effective). Consider taking it today.",
                    category: .supplementReminder,
                    identifier: "supplement-\(remedy.id.uuidString)",
                    at: Date(),
                    hour: hour,
                    minute: minute
                )
            }
        }
    }

    // MARK: - Pattern-Based Alerts

    /// Alert user about detected patterns
    func sendPatternAlert(memory: AIMemory) {
        guard memory.isActive,
              memory.memoryTypeEnum == .pattern || memory.memoryTypeEnum == .correlation,
              memory.confidenceLevel == .high else { return }

        let title: String
        let body: String

        if let trigger = memory.trigger, let symptom = memory.symptom {
            title = "Pattern Detected"
            body = "I've noticed \(trigger) often leads to \(symptom) for you (\(memory.occurrenceCount) times)."
        } else if let notes = memory.notes {
            title = "Health Pattern"
            body = notes
        } else {
            return
        }

        scheduleImmediateNotification(
            title: title,
            body: body,
            category: .patternAlert,
            identifier: "pattern-\(memory.id.uuidString)"
        )
    }

    // MARK: - Clinical Escalation Alerts

    /// Send alerts for patterns that suggest seeing a doctor
    func checkClinicalEscalations(
        logs: [LogEntry],
        rules: [ClinicalEscalationRule] = ClinicalEscalationRule.defaultRules
    ) {
        let now = Date()

        for rule in rules {
            // Get logs within the time window
            let windowStart = Calendar.current.date(byAdding: .day, value: -rule.timeWindowDays, to: now) ?? now
            let relevantLogs = logs.filter { log in
                log.date >= windowStart &&
                (rule.symptom == "Any" || log.symptoms.contains { $0.lowercased().contains(rule.symptom.lowercased()) })
            }

            // Check if rule is triggered
            let occurrences = relevantLogs.count
            let maxSeverity = relevantLogs.map { $0.severity }.max() ?? 0
            let daysSpanned = relevantLogs.isEmpty ? 0 :
                Calendar.current.dateComponents([.day], from: relevantLogs.first!.date, to: now).day ?? 0

            if rule.isTriggered(occurrences: occurrences, maxSeverity: maxSeverity, daysSpanned: daysSpanned) {
                // Only send if we haven't sent this alert recently (within 7 days)
                let alertKey = "doctor-alert-\(rule.symptom)-sent"
                let lastSent = UserDefaults.standard.object(forKey: alertKey) as? Date ?? .distantPast
                let daysSinceLastAlert = Calendar.current.dateComponents([.day], from: lastSent, to: now).day ?? 999

                if daysSinceLastAlert >= 7 {
                    scheduleImmediateNotification(
                        title: "Health Check Suggestion",
                        body: rule.message,
                        category: .doctorRecommendation,
                        identifier: "doctor-\(rule.symptom.lowercased())"
                    )

                    // Mark as sent
                    UserDefaults.standard.set(Date(), forKey: alertKey)
                }
            }
        }
    }

    // MARK: - Morning Wellness Check

    /// Schedule a daily wellness check notification
    func scheduleMorningWellnessCheck(
        memories: [AIMemory],
        screenings: [HealthScreeningSchedule],
        environmentalPressure: String,
        hour: Int = 8,
        minute: Int = 0
    ) {
        var insights: [String] = []

        // Check environmental conditions
        if environmentalPressure.lowercased() == "low" {
            let hasPressureSensitivity = memories.contains { memory in
                memory.isActive &&
                memory.memoryTypeEnum == .trigger &&
                (memory.symptom?.lowercased().contains("headache") == true ||
                 memory.symptom?.lowercased().contains("migraine") == true)
            }
            if hasPressureSensitivity {
                insights.append("Low pressure today - watch for headaches")
            }
        }

        // Check overdue screenings
        let overdueCount = screenings.filter { $0.isEnabled && $0.isOverdue }.count
        if overdueCount > 0 {
            insights.append("\(overdueCount) health screening\(overdueCount > 1 ? "s" : "") overdue")
        }

        // Only send if there are insights
        guard !insights.isEmpty else { return }

        let body = insights.joined(separator: ". ")

        scheduleNotification(
            title: "Good Morning! Here's Your Health Update",
            body: body,
            category: .environmental,
            identifier: "morning-wellness",
            at: Date(),
            hour: hour,
            minute: minute,
            repeats: true
        )
    }

    // MARK: - Private Helpers

    private func scheduleImmediateNotification(
        title: String,
        body: String,
        category: AlertCategory,
        identifier: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.identifier

        // Schedule for 1 second from now (essentially immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(category.identifier)-\(identifier)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.error(error, message: "Error scheduling proactive notification", category: .notification)
            } else {
                Logger.info("Proactive notification scheduled: \(title)", category: .notification)
            }
        }
    }

    private func scheduleNotification(
        title: String,
        body: String,
        category: AlertCategory,
        identifier: String,
        at date: Date,
        hour: Int,
        minute: Int,
        repeats: Bool = false
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.identifier

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)

        let request = UNNotificationRequest(
            identifier: "\(category.identifier)-\(identifier)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.error(error, message: "Error scheduling proactive notification", category: .notification)
            } else {
                Logger.info("Proactive notification scheduled: \(title) at \(hour):\(minute)", category: .notification)
            }
        }
    }

    private func cancelAllNotifications(withPrefix prefix: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.contains(prefix) }
                .map { $0.identifier }

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            Logger.debug("Canceled \(identifiers.count) notifications with prefix: \(prefix)", category: .notification)
        }
    }

    /// Cancel all proactive notifications
    func cancelAllProactiveNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.hasPrefix("proactive-") }
                .map { $0.identifier }

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            Logger.debug("Canceled all proactive notifications: \(identifiers.count)", category: .notification)
        }
    }
}

// MARK: - App Settings Extension

extension ProactiveAlertService {
    /// User preference keys for proactive alerts
    enum SettingsKey: String {
        case enableEnvironmentalAlerts = "enableEnvironmentalAlerts"
        case enableScreeningReminders = "enableScreeningReminders"
        case enableSupplementReminders = "enableSupplementReminders"
        case enablePatternAlerts = "enablePatternAlerts"
        case enableDoctorRecommendations = "enableDoctorRecommendations"
        case morningWellnessCheckHour = "morningWellnessCheckHour"
        case morningWellnessCheckMinute = "morningWellnessCheckMinute"
    }

    var enableEnvironmentalAlerts: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.enableEnvironmentalAlerts.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.enableEnvironmentalAlerts.rawValue) }
    }

    var enableScreeningReminders: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.enableScreeningReminders.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.enableScreeningReminders.rawValue) }
    }

    var enableSupplementReminders: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.enableSupplementReminders.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.enableSupplementReminders.rawValue) }
    }

    var enablePatternAlerts: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.enablePatternAlerts.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.enablePatternAlerts.rawValue) }
    }

    var enableDoctorRecommendations: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.enableDoctorRecommendations.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.enableDoctorRecommendations.rawValue) }
    }

    var morningWellnessCheckHour: Int {
        get {
            let hour = UserDefaults.standard.integer(forKey: SettingsKey.morningWellnessCheckHour.rawValue)
            return hour == 0 ? 8 : hour // Default to 8 AM
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.morningWellnessCheckHour.rawValue) }
    }

    var morningWellnessCheckMinute: Int {
        get { UserDefaults.standard.integer(forKey: SettingsKey.morningWellnessCheckMinute.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.morningWellnessCheckMinute.rawValue) }
    }

    /// Initialize default settings (call once on first launch)
    func initializeDefaultSettings() {
        let defaults: [String: Any] = [
            SettingsKey.enableEnvironmentalAlerts.rawValue: true,
            SettingsKey.enableScreeningReminders.rawValue: true,
            SettingsKey.enableSupplementReminders.rawValue: true,
            SettingsKey.enablePatternAlerts.rawValue: true,
            SettingsKey.enableDoctorRecommendations.rawValue: true,
            SettingsKey.morningWellnessCheckHour.rawValue: 8,
            SettingsKey.morningWellnessCheckMinute.rawValue: 0
        ]

        UserDefaults.standard.register(defaults: defaults)
    }
}
