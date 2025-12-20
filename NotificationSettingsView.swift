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
    
    // Advance notice options
    let advanceNoticeOptions = [0, 15, 30, 60, 120]
    
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
                print("❌ Error sending test notification: \(error.localizedDescription)")
            } else {
                print("✅ Test notification scheduled (will appear in 5 seconds)")
            }
        }
    }
}
