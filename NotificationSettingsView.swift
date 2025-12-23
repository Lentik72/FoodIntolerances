// Create a new file: NotificationSettingsView.swift

import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var hasRequestedPermission = false
    @State private var notificationsEnabled = false
    
    // Local state for the settings
    @State private var enableProtocolReminders: Bool = true
    @State private var enableSymptomReminders: Bool = true
    @State private var enableRefillReminders: Bool = true
    @State private var enableDailySummary: Bool = false
    @State private var defaultReminderTime: Date = Date()
    @State private var dailySummaryTime: Date = Date()
    @State private var reminderAdvanceNotice: Int = 30

    // AI Proactive alert settings
    @State private var enableEnvironmentalAlerts: Bool = true
    @State private var enableScreeningReminders: Bool = true
    @State private var enableSupplementReminders: Bool = true
    @State private var enablePatternAlerts: Bool = true
    @State private var enableDoctorRecommendations: Bool = true
    @State private var morningWellnessTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()

    // Advance notice options
    let advanceNoticeOptions = [0, 15, 30, 60, 120]

    private let proactiveAlertService = ProactiveAlertService.shared
    
    var body: some View {
        Form {
            Section(header: Text("Notification Permissions")) {
                HStack {
                    Text("Notifications")
                    Spacer()
                    if hasRequestedPermission {
                        Text(notificationsEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(notificationsEnabled ? .green : .red)
                    } else {
                        Button("Request Permission") {
                            requestNotificationPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            
            if notificationsEnabled {
                Section(header: Text("General Settings")) {
                    Toggle("Protocol Reminders", isOn: $enableProtocolReminders)
                        .onChange(of: enableProtocolReminders) { _, newValue in
                            notificationManager.updateProtocolRemindersSettings(enabled: newValue)
                        }
                    
                    if enableProtocolReminders {
                        DatePicker("Default Reminder Time", selection: $defaultReminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: defaultReminderTime) { _, newValue in
                                notificationManager.updateDefaultReminderTime(time: newValue)
                            }
                        
                        Picker("Advance Notice", selection: $reminderAdvanceNotice) {
                            Text("None").tag(0)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                        }
                        .onChange(of: reminderAdvanceNotice) { _, newValue in
                            notificationManager.updateReminderAdvanceNotice(minutes: newValue)
                        }
                    }
                    
                    Toggle("Symptom Check-in Reminders", isOn: $enableSymptomReminders)
                        .onChange(of: enableSymptomReminders) { _, newValue in
                            notificationManager.updateSymptomRemindersSettings(enabled: newValue)
                        }
                    
                    Toggle("Refill Reminders", isOn: $enableRefillReminders)
                        .onChange(of: enableRefillReminders) { _, newValue in
                            notificationManager.updateRefillRemindersSettings(enabled: newValue)
                        }
                }
                
                Section(header: Text("Daily Summary")) {
                    Toggle("Enable Daily Summary", isOn: $enableDailySummary)
                        .onChange(of: enableDailySummary) { _, newValue in
                            notificationManager.updateDailySummarySettings(enabled: newValue)
                        }

                    if enableDailySummary {
                        DatePicker("Summary Time", selection: $dailySummaryTime, displayedComponents: .hourAndMinute)
                            .onChange(of: dailySummaryTime) { _, newValue in
                                notificationManager.updateDailySummarySettings(enabled: true, time: newValue)
                            }
                    }
                }

                Section(header: Text("AI Health Assistant Alerts"), footer: Text("Get proactive alerts based on your health patterns and environmental conditions.")) {
                    Toggle("Environmental Alerts", isOn: $enableEnvironmentalAlerts)
                        .onChange(of: enableEnvironmentalAlerts) { _, newValue in
                            proactiveAlertService.enableEnvironmentalAlerts = newValue
                        }

                    Toggle("Health Screening Reminders", isOn: $enableScreeningReminders)
                        .onChange(of: enableScreeningReminders) { _, newValue in
                            proactiveAlertService.enableScreeningReminders = newValue
                        }

                    Toggle("Supplement Reminders", isOn: $enableSupplementReminders)
                        .onChange(of: enableSupplementReminders) { _, newValue in
                            proactiveAlertService.enableSupplementReminders = newValue
                        }

                    Toggle("Pattern Alerts", isOn: $enablePatternAlerts)
                        .onChange(of: enablePatternAlerts) { _, newValue in
                            proactiveAlertService.enablePatternAlerts = newValue
                        }

                    Toggle("Doctor Recommendations", isOn: $enableDoctorRecommendations)
                        .onChange(of: enableDoctorRecommendations) { _, newValue in
                            proactiveAlertService.enableDoctorRecommendations = newValue
                        }

                    DatePicker("Morning Wellness Check", selection: $morningWellnessTime, displayedComponents: .hourAndMinute)
                        .onChange(of: morningWellnessTime) { _, newValue in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                            proactiveAlertService.morningWellnessCheckHour = components.hour ?? 8
                            proactiveAlertService.morningWellnessCheckMinute = components.minute ?? 0
                        }
                }

                Section(header: Text("Test Notifications")) {
                    Button("Send Test Notification") {
                        sendTestNotification()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Notification Settings")
        .onAppear {
            // Load current settings
            loadCurrentSettings()
            checkNotificationStatus()
        }
    }
    
    private func loadCurrentSettings() {
        // Get settings from NotificationManager
        enableProtocolReminders = UserDefaults.standard.bool(forKey: "enableProtocolReminders")
        enableSymptomReminders = UserDefaults.standard.bool(forKey: "enableSymptomReminders")
        enableRefillReminders = UserDefaults.standard.bool(forKey: "enableRefillReminders")
        enableDailySummary = UserDefaults.standard.bool(forKey: "dailySummaryEnabled")

        if let time = UserDefaults.standard.object(forKey: "defaultReminderTimeRaw") as? Double {
            defaultReminderTime = Date(timeIntervalSince1970: time)
        }

        if let time = UserDefaults.standard.object(forKey: "dailySummaryTimeRaw") as? Double {
            dailySummaryTime = Date(timeIntervalSince1970: time)
        }

        reminderAdvanceNotice = UserDefaults.standard.integer(forKey: "reminderAdvanceNoticeMinutes")

        // Load proactive alert settings
        enableEnvironmentalAlerts = proactiveAlertService.enableEnvironmentalAlerts
        enableScreeningReminders = proactiveAlertService.enableScreeningReminders
        enableSupplementReminders = proactiveAlertService.enableSupplementReminders
        enablePatternAlerts = proactiveAlertService.enablePatternAlerts
        enableDoctorRecommendations = proactiveAlertService.enableDoctorRecommendations

        // Load morning wellness time
        var components = DateComponents()
        components.hour = proactiveAlertService.morningWellnessCheckHour
        components.minute = proactiveAlertService.morningWellnessCheckMinute
        if let time = Calendar.current.date(from: components) {
            morningWellnessTime = time
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasRequestedPermission = settings.authorizationStatus != .notDetermined
                self.notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func requestNotificationPermission() {
        notificationManager.requestNotificationPermission { granted in
            self.hasRequestedPermission = true
            self.notificationsEnabled = granted
        }
    }
    
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification to verify that your settings are working correctly."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.error(error, message: "Error sending test notification", category: .notification)
            } else {
                Logger.info("Test notification scheduled (will appear in 5 seconds)", category: .notification)
            }
        }
    }
}
