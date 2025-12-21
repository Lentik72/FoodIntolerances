import SwiftUI
import SwiftData

struct EditProtocolSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var therapyProtocol: TherapyProtocol
    @Binding var isPresented: Bool

    // State variables for editing
    @State private var title: String
    @State private var category: String
    @State private var instructions: String
    @State private var frequency: String
    @State private var timeOfDay: String
    @State private var duration: String
    @State private var symptomsString: String
    @State private var tagsString: String
    @State private var notes: String
    @State private var isWishlist: Bool
    @State private var isActive: Bool // ✅ Active/Inactive Toggle
    @State private var startDate: Date
    @State private var endDate: Date?

    // 🔔 Reminder Settings
    @State private var enableReminder: Bool
    @State private var reminderTime: Date

    init(therapyProtocol: Binding<TherapyProtocol>, isPresented: Binding<Bool>) {
        self._therapyProtocol = therapyProtocol
        self._isPresented = isPresented
        let proto = therapyProtocol.wrappedValue

        // Initialize states with existing protocol data
        _title = State(initialValue: proto.title)
        _category = State(initialValue: proto.category)
        _instructions = State(initialValue: proto.instructions)
        _frequency = State(initialValue: proto.frequency)
        _timeOfDay = State(initialValue: proto.timeOfDay)
        _duration = State(initialValue: proto.duration)
        _symptomsString = State(initialValue: proto.symptoms?.joined(separator: ", ") ?? "")
        _tagsString = State(initialValue: proto.tags?.joined(separator: ", ") ?? "")
        _notes = State(initialValue: proto.notes ?? "")
        _isWishlist = State(initialValue: proto.isWishlist)
        _isActive = State(initialValue: proto.isActive) // ✅ Active state
        _startDate = State(initialValue: proto.startDate)
        _endDate = State(initialValue: proto.endDate)
        _enableReminder = State(initialValue: proto.enableReminder)
        _reminderTime = State(initialValue: proto.reminderTime ?? Date()) // ✅ Default reminder time if not set
    }

    var body: some View {
        NavigationStack {
            Form {
                // 📌 GENERAL INFORMATION
                Section(header: Text("General Information").font(.headline)) {
                    TextField("Title", text: $title)
                    TextField("Category", text: $category)

                    // ✅ Active/Inactive Toggle
                    Toggle("Active Protocol", isOn: $isActive)
                        .tint(isActive ? .green : .red)
                }

                // 🔔 REMINDER SETTINGS
                Section(header: Text("Reminder Settings").font(.headline)) {
                    Toggle("Enable Reminder", isOn: $enableReminder)

                    if enableReminder {
                        DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(WheelDatePickerStyle())
                    }
                }

                // 📋 INSTRUCTIONS & TIMING
                Section(header: Text("Instructions & Timing").font(.headline)) {
                    TextField("Instructions", text: $instructions)
                    TextField("Frequency", text: $frequency)
                    TextField("Time of Day", text: $timeOfDay)
                    TextField("Duration", text: $duration)
                }

                // 📝 TRACKING & NOTES
                Section(header: Text("Tracking & Notes").font(.headline)) {
                    TextField("Symptoms (comma-separated)", text: $symptomsString)
                    TextField("Tags (comma-separated)", text: $tagsString)
                    Toggle("Wishlist?", isOn: $isWishlist)
                    TextField("Notes", text: $notes)
                }

                // ✅ SAVE BUTTON
                Button(action: saveProtocol) {
                    Label("Save Changes", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
                .padding(.top, 10)
            }
            .navigationTitle("Edit Protocol")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }

    // 💾 SAVE PROTOCOL & MANAGE REMINDERS
    private func saveProtocol() {
        therapyProtocol.title = title
        therapyProtocol.category = category
        therapyProtocol.instructions = instructions
        therapyProtocol.frequency = frequency
        therapyProtocol.timeOfDay = timeOfDay
        therapyProtocol.duration = duration
        therapyProtocol.symptoms = symptomsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        therapyProtocol.tags = tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        therapyProtocol.notes = notes.isEmpty ? nil : notes
        therapyProtocol.isWishlist = isWishlist
        therapyProtocol.isActive = isActive // ✅ Save active state
        therapyProtocol.startDate = startDate
        therapyProtocol.endDate = endDate
        therapyProtocol.enableReminder = enableReminder
        therapyProtocol.reminderTime = reminderTime

        // 🔔 Manage Notifications
        if enableReminder {
            NotificationManager.shared.scheduleReminder(for: therapyProtocol)
        } else {
            NotificationManager.shared.cancelReminder(for: therapyProtocol)
        }

        // ✅ Save the changes to the database
        do {
            try modelContext.save()
            isPresented = false
        } catch {
            print("❌ Error saving protocol changes: \(error)")
        }
    }
}
