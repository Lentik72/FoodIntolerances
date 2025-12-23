import SwiftUI
import SwiftData

/// View for viewing and editing user profile settings
struct UserProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var userProfiles: [UserProfile]

    // Editing state
    @State private var age: String = ""
    @State private var gender: String = ""
    @State private var selectedConditions: Set<String> = []
    @State private var activityLevel: String = ""
    @State private var dietType: String = ""
    @State private var targetSleepHours: Double = 8.0
    @State private var memoryLevel: AIMemoryLevel = .patterns

    // UI State
    @State private var showConditionsPicker = false
    @State private var hasChanges = false

    private var profile: UserProfile? {
        userProfiles.first
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info Section
                Section("Basic Information") {
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("Enter age", text: $age)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: age) { _, _ in hasChanges = true }
                    }

                    Picker("Gender", selection: $gender) {
                        Text("Select").tag("")
                        ForEach(Gender.allCases, id: \.rawValue) { g in
                            Text(g.rawValue).tag(g.rawValue)
                        }
                    }
                    .onChange(of: gender) { _, _ in hasChanges = true }
                }

                // Health Conditions Section
                Section {
                    NavigationLink {
                        HealthConditionsPickerView(selectedConditions: $selectedConditions)
                    } label: {
                        HStack {
                            Text("Health Conditions")
                            Spacer()
                            if selectedConditions.isEmpty {
                                Text("None")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(selectedConditions.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Health Conditions")
                } footer: {
                    if !selectedConditions.isEmpty {
                        Text(selectedConditions.sorted().joined(separator: ", "))
                            .font(.caption)
                    }
                }

                // Lifestyle Section
                Section("Lifestyle") {
                    Picker("Activity Level", selection: $activityLevel) {
                        Text("Select").tag("")
                        ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                            Text(level.rawValue).tag(level.rawValue)
                        }
                    }
                    .onChange(of: activityLevel) { _, _ in hasChanges = true }

                    Picker("Diet Type", selection: $dietType) {
                        Text("Select").tag("")
                        ForEach(DietType.allCases, id: \.rawValue) { diet in
                            Text(diet.rawValue).tag(diet.rawValue)
                        }
                    }
                    .onChange(of: dietType) { _, _ in hasChanges = true }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Target Sleep")
                            Spacer()
                            Text("\(targetSleepHours, specifier: "%.1f") hours")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $targetSleepHours, in: 4...12, step: 0.5)
                            .onChange(of: targetSleepHours) { _, _ in hasChanges = true }
                    }
                }

                // AI Memory Section
                Section {
                    Picker("Memory Detail Level", selection: $memoryLevel) {
                        ForEach(AIMemoryLevel.allCases, id: \.rawValue) { level in
                            VStack(alignment: .leading) {
                                Text(level.displayName)
                            }
                            .tag(level)
                        }
                    }
                    .onChange(of: memoryLevel) { _, _ in hasChanges = true }
                } header: {
                    Text("AI Memory Preferences")
                } footer: {
                    Text(memoryLevel.description)
                }

                // Navigation to related views
                Section("Manage") {
                    NavigationLink(destination: AllergyManagementView()) {
                        HStack {
                            Image(systemName: "allergens")
                                .foregroundColor(.orange)
                            Text("Allergies & Sensitivities")
                        }
                    }

                    NavigationLink(destination: HealthTestsListView()) {
                        HStack {
                            Image(systemName: "testtube.2")
                                .foregroundColor(.blue)
                            Text("Health Test Results")
                        }
                    }

                    NavigationLink(destination: HealthScreeningsView()) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.purple)
                            Text("Health Screenings")
                        }
                    }
                }

                // Onboarding status
                if let profile = profile {
                    Section("Setup Status") {
                        HStack {
                            Text("Onboarding")
                            Spacer()
                            if profile.hasCompletedOnboarding {
                                Label("Completed", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Label("Incomplete", systemImage: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                            }
                        }

                        if let date = profile.onboardingCompletedDate {
                            HStack {
                                Text("Completed On")
                                Spacer()
                                Text(date, style: .date)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if hasChanges {
                        Button("Save") {
                            saveChanges()
                        }
                    }
                }
            }
            .onAppear {
                loadProfile()
            }
        }
    }

    private func loadProfile() {
        guard let profile = profile else { return }

        if let profileAge = profile.age {
            age = String(profileAge)
        }
        gender = profile.gender ?? ""
        selectedConditions = Set(profile.healthConditions)
        activityLevel = profile.activityLevel ?? ""
        dietType = profile.dietType ?? ""
        targetSleepHours = profile.targetSleepHours
        memoryLevel = AIMemoryLevel(rawValue: profile.memoryLevel) ?? .patterns

        hasChanges = false
    }

    private func saveChanges() {
        let profile: UserProfile
        if let existingProfile = self.profile {
            profile = existingProfile
        } else {
            profile = UserProfile()
            modelContext.insert(profile)
        }

        profile.age = Int(age)
        profile.gender = gender.isEmpty ? nil : gender
        profile.healthConditions = Array(selectedConditions)
        profile.activityLevel = activityLevel.isEmpty ? nil : activityLevel
        profile.dietType = dietType.isEmpty ? nil : dietType
        profile.targetSleepHours = targetSleepHours
        profile.memoryLevel = memoryLevel.rawValue
        profile.lastUpdated = Date()

        do {
            try modelContext.save()
            hasChanges = false
            Logger.info("Profile saved successfully", category: .data)
        } catch {
            Logger.error(error, message: "Failed to save profile", category: .data)
        }
    }
}

// MARK: - Health Conditions Picker

struct HealthConditionsPickerView: View {
    @Binding var selectedConditions: Set<String>
    @State private var customCondition: String = ""

    var body: some View {
        List {
            ForEach(CommonHealthCondition.all, id: \.self) { condition in
                Button(action: {
                    if selectedConditions.contains(condition) {
                        selectedConditions.remove(condition)
                    } else {
                        selectedConditions.insert(condition)
                    }
                }) {
                    HStack {
                        Text(condition)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedConditions.contains(condition) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            Section("Add Custom") {
                HStack {
                    TextField("Other condition", text: $customCondition)
                    Button(action: {
                        if !customCondition.isEmpty {
                            selectedConditions.insert(customCondition)
                            customCondition = ""
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(customCondition.isEmpty)
                }
            }
        }
        .navigationTitle("Health Conditions")
    }
}

// MARK: - Placeholder Views

struct HealthTestsListView: View {
    @Query private var testResults: [HealthTestResult]

    var body: some View {
        List {
            if testResults.isEmpty {
                ContentUnavailableView(
                    "No Test Results",
                    systemImage: "testtube.2",
                    description: Text("Add your lab results to track your health over time")
                )
            } else {
                ForEach(testResults) { result in
                    VStack(alignment: .leading) {
                        Text(result.testName)
                            .font(.headline)
                        Text("\(result.formattedValue)")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Test Results")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AddHealthTestView()) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct AddHealthTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var testName: String = ""
    @State private var value: String = ""
    @State private var unit: String = ""
    @State private var testDate: Date = Date()

    var body: some View {
        Form {
            Section("Test Information") {
                TextField("Test Name", text: $testName)
                TextField("Value", text: $value)
                    .keyboardType(.decimalPad)
                TextField("Unit (e.g., mg/dL)", text: $unit)
                DatePicker("Test Date", selection: $testDate, displayedComponents: .date)
            }

            Section {
                Button("Save Test Result") {
                    saveTest()
                }
                .disabled(testName.isEmpty || value.isEmpty)
            }
        }
        .navigationTitle("Add Test Result")
    }

    private func saveTest() {
        let test = HealthTestResult(
            testName: testName,
            value: value,
            unit: unit.isEmpty ? nil : unit,
            testDate: testDate
        )
        modelContext.insert(test)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            Logger.error(error, message: "Failed to save test result", category: .data)
        }
    }
}

struct HealthScreeningsView: View {
    @Query private var screenings: [HealthScreeningSchedule]

    var body: some View {
        List {
            if screenings.isEmpty {
                ContentUnavailableView(
                    "No Screenings Scheduled",
                    systemImage: "calendar.badge.clock",
                    description: Text("Set up your profile to get personalized screening reminders")
                )
            } else {
                ForEach(screenings) { screening in
                    VStack(alignment: .leading) {
                        Text(screening.screeningName)
                            .font(.headline)
                        Text(screening.frequencyDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Health Screenings")
    }
}

#Preview {
    UserProfileView()
        .modelContainer(for: [UserProfile.self, UserAllergy.self, HealthTestResult.self, HealthScreeningSchedule.self], inMemory: true)
}
