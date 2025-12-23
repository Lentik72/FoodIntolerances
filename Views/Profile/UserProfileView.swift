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

    // Optional Health Details (height/weight)
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    @State private var heightCm: String = ""
    @State private var weightLbs: String = ""
    @State private var weightKg: String = ""
    @State private var unitPreference: String = "imperial"

    // UI State
    @State private var showConditionsPicker = false
    @State private var hasChanges = false
    @State private var showClearMeasurementsAlert = false

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

                // Optional Health Details Section
                Section {
                    Picker("Units", selection: $unitPreference) {
                        Text("Imperial (ft, lbs)").tag("imperial")
                        Text("Metric (cm, kg)").tag("metric")
                    }
                    .onChange(of: unitPreference) { _, _ in hasChanges = true }

                    if unitPreference == "imperial" {
                        HStack {
                            Text("Height")
                            Spacer()
                            TextField("ft", text: $heightFeet)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 40)
                                .onChange(of: heightFeet) { _, _ in hasChanges = true }
                            Text("'")
                            TextField("in", text: $heightInches)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 40)
                                .onChange(of: heightInches) { _, _ in hasChanges = true }
                            Text("\"")
                        }

                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("lbs", text: $weightLbs)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .onChange(of: weightLbs) { _, _ in hasChanges = true }
                            Text("lbs")
                        }
                    } else {
                        HStack {
                            Text("Height")
                            Spacer()
                            TextField("cm", text: $heightCm)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .onChange(of: heightCm) { _, _ in hasChanges = true }
                            Text("cm")
                        }

                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("kg", text: $weightKg)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .onChange(of: weightKg) { _, _ in hasChanges = true }
                            Text("kg")
                        }
                    }

                    if profile?.heightCm != nil || profile?.weightKg != nil {
                        Button(role: .destructive) {
                            showClearMeasurementsAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Measurements")
                            }
                        }
                    }
                } header: {
                    Text("Optional Health Details")
                } footer: {
                    Text("Used to improve health context and screening suggestions. This is optional and can be removed anytime.")
                        .font(.caption)
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
            .alert("Clear Measurements?", isPresented: $showClearMeasurementsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearMeasurements()
                }
            } message: {
                Text("This will remove your height and weight data. You can add it again anytime.")
            }
        }
    }

    private func clearMeasurements() {
        profile?.clearBodyMeasurements()
        heightFeet = ""
        heightInches = ""
        heightCm = ""
        weightLbs = ""
        weightKg = ""
        try? modelContext.save()
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
        unitPreference = profile.unitPreference

        // Load height/weight
        if let cm = profile.heightCm {
            if unitPreference == "imperial" {
                let totalInches = cm / 2.54
                let feet = Int(totalInches / 12)
                let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
                heightFeet = String(feet)
                heightInches = String(inches)
            } else {
                heightCm = String(Int(cm))
            }
        }

        if let kg = profile.weightKg {
            if unitPreference == "imperial" {
                let lbs = Int(kg * 2.20462)
                weightLbs = String(lbs)
            } else {
                weightKg = String(Int(kg))
            }
        }

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
        profile.unitPreference = unitPreference

        // Save height (convert to cm for internal storage)
        if unitPreference == "imperial" {
            if let feet = Double(heightFeet), let inches = Double(heightInches) {
                let totalInches = (feet * 12) + inches
                profile.heightCm = totalInches * 2.54
                profile.bodyMeasurementsUpdated = Date()
            } else if heightFeet.isEmpty && heightInches.isEmpty {
                // Don't clear if just empty - user might not have entered yet
            }
        } else {
            if let cm = Double(heightCm) {
                profile.heightCm = cm
                profile.bodyMeasurementsUpdated = Date()
            }
        }

        // Save weight (convert to kg for internal storage)
        if unitPreference == "imperial" {
            if let lbs = Double(weightLbs) {
                profile.weightKg = lbs / 2.20462
                profile.bodyMeasurementsUpdated = Date()
            }
        } else {
            if let kg = Double(weightKg) {
                profile.weightKg = kg
                profile.bodyMeasurementsUpdated = Date()
            }
        }

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
