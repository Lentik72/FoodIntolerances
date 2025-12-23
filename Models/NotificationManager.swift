// Update to NotificationManager.swift

import UserNotifications
import Foundation
import SwiftUI

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    // User settings with defaults
    @AppStorage("enableProtocolReminders") private var enableProtocolReminders: Bool = true
    @AppStorage("enableSymptomReminders") private var enableSymptomReminders: Bool = true
    @AppStorage("defaultReminderTime") private var defaultReminderTimeRaw: Double = Date().timeIntervalSince1970
    @AppStorage("reminderAdvanceNoticeMinutes") private var reminderAdvanceNoticeMinutes: Int = 30
    @AppStorage("enableRefillReminders") private var enableRefillReminders: Bool = true
    @AppStorage("dailySummaryEnabled") private var dailySummaryEnabled: Bool = false
    @AppStorage("dailySummaryTime") private var dailySummaryTimeRaw: Double = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    
    // Computed property to get the default reminder time as a Date
    var defaultReminderTime: Date {
        get { Date(timeIntervalSince1970: defaultReminderTimeRaw) }
        set { defaultReminderTimeRaw = newValue.timeIntervalSince1970 }
    }
    
    // Computed property to get the daily summary time as a Date
    var dailySummaryTime: Date {
        get { Date(timeIntervalSince1970: dailySummaryTimeRaw) }
        set { dailySummaryTimeRaw = newValue.timeIntervalSince1970 }
    }

    private init() {}

    // MARK: - Public Settings Methods
    
    func updateProtocolRemindersSettings(enabled: Bool) {
        enableProtocolReminders = enabled
        
        // If disabled, cancel all protocol reminders
        if !enabled {
            cancelAllProtocolReminders()
        } else {
            // Reschedule active protocols
            rescheduleAllProtocolReminders()
        }
    }
    
    func updateSymptomRemindersSettings(enabled: Bool) {
        enableSymptomReminders = enabled
        
        // If disabled, cancel all symptom reminders
        if !enabled {
            cancelAllSymptomReminders()
        } else {
            // Reschedule active symptom check-ins
            rescheduleAllSymptomReminders()
        }
    }
    
    func updateRefillRemindersSettings(enabled: Bool) {
        enableRefillReminders = enabled
    }
    
    func updateDailySummarySettings(enabled: Bool, time: Date? = nil) {
        dailySummaryEnabled = enabled
        if let time = time {
            dailySummaryTime = time
        }
        
        if enabled {
            scheduleDailySummary()
        } else {
            cancelDailySummary()
        }
    }
    
    func updateDefaultReminderTime(time: Date) {
        defaultReminderTime = time
    }
    
    func updateReminderAdvanceNotice(minutes: Int) {
        reminderAdvanceNoticeMinutes = minutes
    }
    
    // MARK: - Permission Request
    
    func requestNotificationPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                Logger.error(error, message: "Error requesting notifications", category: .notification)
            } else {
                Logger.info(granted ? "Notifications enabled" : "Notifications denied", category: .notification)
            }

            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    // MARK: - Protocol Reminders
    
    func scheduleReminder(for therapyProtocol: TherapyProtocol) {
        guard enableProtocolReminders && therapyProtocol.isActive else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(therapyProtocol.title)"
        content.body = "It's time for your scheduled therapy: \(therapyProtocol.instructions)"
        content.sound = .default
        
        // Use protocol's reminder time or default if not set
        let reminderTime = therapyProtocol.reminderTime ?? defaultReminderTime
        
        var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        dateComponents.second = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(identifier: "protocol-\(therapyProtocol.id.uuidString)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.error(error, message: "Error scheduling protocol notification", category: .notification)
            } else {
                Logger.info("Protocol notification scheduled for \(therapyProtocol.title) at \(dateComponents.hour ?? 0):\(dateComponents.minute ?? 0)", category: .notification)
            }
        }

        // Schedule advance reminder if enabled
        if reminderAdvanceNoticeMinutes > 0 {
            scheduleAdvanceReminder(for: therapyProtocol, minutes: reminderAdvanceNoticeMinutes, baseTime: reminderTime)
        }
    }
    
    func cancelReminder(for therapyProtocol: TherapyProtocol) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [
                    "protocol-\(therapyProtocol.id.uuidString)",
                    "protocol-advance-\(therapyProtocol.id.uuidString)"
                ]
            )
            Logger.debug("Canceled notifications for \(therapyProtocol.title)", category: .notification)
        }
        
        private func scheduleAdvanceReminder(for therapyProtocol: TherapyProtocol, minutes: Int, baseTime: Date) {
            let content = UNMutableNotificationContent()
            content.title = "Upcoming: \(therapyProtocol.title)"
            content.body = "Your protocol is scheduled in \(minutes) minutes"
            content.sound = .default
            
            // Calculate advanced time
            let advancedTime = Calendar.current.date(byAdding: .minute, value: -minutes, to: baseTime) ?? baseTime
            
            var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: advancedTime)
            dateComponents.second = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
            let request = UNNotificationRequest(
                identifier: "protocol-advance-\(therapyProtocol.id.uuidString)",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Logger.error(error, message: "Error scheduling advance protocol notification", category: .notification)
                } else {
                    Logger.info("Advance protocol notification scheduled for \(therapyProtocol.title)", category: .notification)
                }
            }
        }
        
        private func cancelAllProtocolReminders() {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let protocolIdentifiers = requests
                    .filter { $0.identifier.hasPrefix("protocol-") }
                    .map { $0.identifier }
                
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: protocolIdentifiers)
                Logger.debug("Canceled all protocol notifications: \(protocolIdentifiers.count) notifications removed", category: .notification)
            }
        }
        
        private func rescheduleAllProtocolReminders() {
            // This method would need to access all active protocols from the model context
            // Since we can't directly access ModelContext here, this would be called from a view
            // that passes the protocols to reschedule
            Logger.warning("rescheduleAllProtocolReminders should be called with protocols from a view", category: .notification)
        }
        
        // MARK: - Symptom Check-In Reminders
        
        func scheduleSymptomCheckIn(for symptom: OngoingSymptom, at reminderTime: Date) {
            guard enableSymptomReminders else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Symptom Check-in: \(symptom.name)"
            content.body = "Time to log your \(symptom.name) symptom status"
            content.sound = .default

            var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            dateComponents.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            let request = UNNotificationRequest(
                identifier: "symptom-checkin-\(symptom.id.uuidString)",
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Logger.error(error, message: "Error scheduling symptom check-in notification", category: .notification)
                } else {
                    Logger.info("Notification scheduled for \(symptom.name) at \(dateComponents.hour ?? 0):\(dateComponents.minute ?? 0)", category: .notification)
                }
            }
        }
        
        func cancelSymptomCheckInNotification(for symptom: OngoingSymptom) {
            let identifier = "symptom-checkin-\(symptom.id.uuidString)"
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            Logger.debug("Canceled symptom check-in notification for \(symptom.name)", category: .notification)
        }
        
        private func cancelAllSymptomReminders() {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let symptomIdentifiers = requests
                    .filter { $0.identifier.hasPrefix("symptom-checkin-") }
                    .map { $0.identifier }
                
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: symptomIdentifiers)
                Logger.debug("Canceled all symptom check-in notifications: \(symptomIdentifiers.count) notifications removed", category: .notification)
            }
        }
        
        private func rescheduleAllSymptomReminders() {
            // This method would need to access all ongoing symptoms from the model context
            // Since we can't directly access ModelContext here, this would be called from a view
            // that passes the symptoms to reschedule
            Logger.warning("rescheduleAllSymptomReminders should be called with symptoms from a view", category: .notification)
        }
        
        // MARK: - Refill Reminders
        
        func scheduleRefillReminder(for item: CabinetItem) {
            guard enableRefillReminders else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Low Supply Alert"
            content.body = "You're running low on \(item.name). Consider restocking soon."
            content.sound = .default
            
            // Schedule notification to appear immediately
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            
            let request = UNNotificationRequest(
                identifier: "refill-\(item.id.uuidString)",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Logger.error(error, message: "Error scheduling refill notification", category: .notification)
                } else {
                    Logger.info("Refill notification scheduled for \(item.name)", category: .notification)
                }
            }
        }
        
        // MARK: - Daily Summary Notification
        
        func scheduleDailySummary() {
            guard dailySummaryEnabled else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Daily Health Summary"
            content.body = "Check your daily health summary and upcoming protocols"
            content.sound = .default
            
            var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: dailySummaryTime)
            dateComponents.second = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
            let request = UNNotificationRequest(
                identifier: "daily-summary",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Logger.error(error, message: "Error scheduling daily summary notification", category: .notification)
                } else {
                    Logger.info("Daily summary notification scheduled for \(dateComponents.hour ?? 0):\(dateComponents.minute ?? 0)", category: .notification)
                }
            }
        }
        
        func cancelDailySummary() {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-summary"])
            Logger.debug("Canceled daily summary notification", category: .notification)
        }
    }
