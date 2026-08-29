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
    /// Source of truth for `currentAge` when present; `age` above is the
    /// fallback (see `PersonProfile.currentAge`). Optional in the UI, not
    /// just in storage — nil renders as "not set", never a bogus default.
    @State private var dateOfBirth: Date?
    @State private var selectedConditions: Set<String> = []
    @State private var activityLevel: String = ""
    @State private var dietType: String = ""
    @State private var targetSleepHours: Double = 8.0
    @State private var memoryLevel: AIMemoryLevel = .patterns

    // Optional Health Details (height only — weight is a series now, read
    // from HealthKit-derived events, not this write-only profile column;
    // see the round's decision record:
    // docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md).
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    @State private var heightCm: String = ""
    @State private var unitPreference: String = "imperial"
    @AppStorage("hg.measurementSystem") private var rawUnitSystem = ""

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
                Section {
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("Enter age", text: $age)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: age) { _, _ in hasChanges = true }
                    }

                    HStack {
                        Text("Date of Birth")
                        Spacer()
                        DatePicker(
                            "Date of Birth",
                            selection: Binding($dateOfBirth, replacingNilWith: defaultDateOfBirth),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .onChange(of: dateOfBirth) { _, newValue in
                            hasChanges = true
                            // A manual pick is the user re-asserting a DOB — lift the
                            // "Remove Date of Birth" tombstone so a later HealthKit
                            // authorization pass isn't blocked by an old removal.
                            if newValue != nil {
                                UserDefaults.standard.set(false, forKey: HealthKitIngestor.dobRemovedKey)
                            }
                        }
                    }

                    if dateOfBirth != nil {
                        Button(role: .destructive) {
                            dateOfBirth = nil
                            hasChanges = true
                            // Tombstone the removal so populateProfileFromHealthKitCharacteristics
                            // never silently repopulates what was just removed.
                            UserDefaults.standard.set(true, forKey: HealthKitIngestor.dobRemovedKey)
                        } label: {
                            Text("Remove Date of Birth")
                        }
                    }

                    Picker("Gender", selection: $gender) {
                        Text("Select").tag("")
                        ForEach(Gender.allCases, id: \.rawValue) { g in
                            Text(g.rawValue).tag(g.rawValue)
                        }
                    }
                    .onChange(of: gender) { _, _ in hasChanges = true }
                } header: {
                    Text("Basic Information")
                } footer: {
                    Text("Date of birth is used for age-based health screening when available. Age is the fallback when it isn't set.")
                        .font(.caption)
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

    /// A plausible placeholder shown the first time the picker opens on an
    /// unset date of birth; nothing is written until the user actually picks
    /// a date (`Binding($dateOfBirth, replacingNilWith:)` only writes on
    /// `set`, never on `get`).
    private var defaultDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    }

    private func clearMeasurements() {
        profile?.clearBodyMeasurements()
        heightFeet = ""
        heightInches = ""
        heightCm = ""
        try? modelContext.save()
    }

    private func loadProfile() {
        guard let profile = profile else {
            unitPreference = UnitSystem.newProfileUnitPreference(global: rawUnitSystem)
            return
        }

        if let profileAge = profile.age {
            age = String(profileAge)
        }
        dateOfBirth = profile.dateOfBirth
        gender = profile.gender ?? ""
        selectedConditions = Set(profile.healthConditions)
        activityLevel = profile.activityLevel ?? ""
        dietType = profile.dietType ?? ""
        targetSleepHours = profile.targetSleepHours
        memoryLevel = AIMemoryLevel(rawValue: profile.memoryLevel) ?? .patterns
        unitPreference = profile.unitPreference

        // Load height (weight is a series now — see the Optional Health
        // Details declaration above — so this view never reads weightKg).
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
        profile.dateOfBirth = dateOfBirth
        profile.gender = gender.isEmpty ? nil : gender
        profile.healthConditions = Array(selectedConditions)
        profile.activityLevel = activityLevel.isEmpty ? nil : activityLevel
        profile.dietType = dietType.isEmpty ? nil : dietType
        profile.targetSleepHours = targetSleepHours
        profile.memoryLevel = memoryLevel.rawValue

        // Normalize before publishing to either store: a valid picker choice wins,
        // else fall back to the resolved global (which is always valid).
        let selectedSystem = UnitSystem(rawValue: unitPreference)
            ?? UnitSystem.resolved(from: rawUnitSystem)
        let normalizedPreference = selectedSystem.rawValue
        profile.unitPreference = normalizedPreference

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

        profile.lastUpdated = Date()

        do {
            try modelContext.save()
            hasChanges = false
            rawUnitSystem = normalizedPreference           // rule 5: publish the NORMALIZED value only on a successful save
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
