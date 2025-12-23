import SwiftUI
import SwiftData

/// Main container that coordinates the onboarding flow
struct OnboardingContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: OnboardingStep = .welcome
    @State private var userProfile: UserProfile?

    // Collected data during onboarding
    @State private var age: Int?
    @State private var gender: String?
    @State private var healthConditions: Set<String> = []
    @State private var selectedAllergies: [OnboardingAllergy] = []
    @State private var ongoingSymptoms: Set<String> = []
    @State private var medications: [String] = []
    @State private var supplements: Set<String> = []
    @State private var memoryLevel: AIMemoryLevel = .patterns

    var onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressBar(currentStep: currentStep)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Content
                TabView(selection: $currentStep) {
                    OnboardingWelcomeStep(
                        age: $age,
                        gender: $gender,
                        onNext: { advanceToStep(.healthConditions) }
                    )
                    .tag(OnboardingStep.welcome)

                    OnboardingConditionsStep(
                        selectedConditions: $healthConditions,
                        onNext: { advanceToStep(.allergies) },
                        onBack: { advanceToStep(.welcome) }
                    )
                    .tag(OnboardingStep.healthConditions)

                    OnboardingAllergiesStep(
                        selectedAllergies: $selectedAllergies,
                        onNext: { advanceToStep(.symptoms) },
                        onBack: { advanceToStep(.healthConditions) }
                    )
                    .tag(OnboardingStep.allergies)

                    OnboardingSymptomsStep(
                        selectedSymptoms: $ongoingSymptoms,
                        onNext: { advanceToStep(.medications) },
                        onBack: { advanceToStep(.allergies) }
                    )
                    .tag(OnboardingStep.symptoms)

                    OnboardingMedicationsStep(
                        medications: $medications,
                        supplements: $supplements,
                        onNext: { advanceToStep(.memory) },
                        onBack: { advanceToStep(.symptoms) }
                    )
                    .tag(OnboardingStep.medications)

                    OnboardingMemoryStep(
                        memoryLevel: $memoryLevel,
                        onNext: { advanceToStep(.complete) },
                        onBack: { advanceToStep(.medications) }
                    )
                    .tag(OnboardingStep.memory)

                    OnboardingCompleteStep(
                        allergiesCount: selectedAllergies.count,
                        symptomsCount: ongoingSymptoms.count,
                        supplementsCount: supplements.count + medications.count,
                        onFinish: completeOnboarding
                    )
                    .tag(OnboardingStep.complete)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if currentStep != .complete {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func advanceToStep(_ step: OnboardingStep) {
        withAnimation {
            currentStep = step
        }
    }

    private func completeOnboarding() {
        // Create or update UserProfile
        let profile = UserProfile(
            age: age,
            gender: gender,
            healthConditions: Array(healthConditions),
            memoryLevel: memoryLevel.rawValue
        )
        profile.hasCompletedOnboarding = true
        profile.onboardingCompletedDate = Date()
        profile.onboardingStepsCompleted = 7

        modelContext.insert(profile)

        // Create UserAllergy entries
        for allergy in selectedAllergies {
            let userAllergy = UserAllergy(
                name: allergy.name,
                allergyType: allergy.type,
                severity: allergy.severity,
                crossReactiveItems: allergy.crossReactiveItems
            )
            modelContext.insert(userAllergy)
        }

        // Create OngoingSymptom entries (if model exists)
        // Note: This would integrate with existing OngoingSymptom model

        // Save
        do {
            try modelContext.save()
            Logger.info("Onboarding completed successfully", category: .app)

            // Build initial AI memories from existing logs
            buildInitialMemories(profile: profile)
        } catch {
            Logger.error(error, message: "Failed to save onboarding data", category: .data)
        }

        onComplete()
    }

    /// Build initial AI memories from existing log history
    private func buildInitialMemories(profile: UserProfile) {
        // Fetch existing logs
        let logsDescriptor = FetchDescriptor<LogEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let existingLogs = try? modelContext.fetch(logsDescriptor),
              !existingLogs.isEmpty else {
            Logger.debug("No existing logs to build memories from", category: .data)
            return
        }

        // Fetch tracked items (supplements, medications)
        let trackedDescriptor = FetchDescriptor<TrackedItem>()
        let trackedItems = (try? modelContext.fetch(trackedDescriptor)) ?? []

        // Get memory level from profile
        let memoryLevel = AIMemoryLevel(rawValue: profile.memoryLevel) ?? .patterns

        // Build memories
        let memoryService = UserMemoryService()
        let memories = memoryService.buildInitialMemories(
            from: existingLogs,
            treatments: trackedItems,
            context: modelContext,
            memoryLevel: memoryLevel
        )

        Logger.info("Built \(memories.count) initial AI memories from \(existingLogs.count) logs", category: .data)
    }
}

// MARK: - Onboarding Step Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case healthConditions = 1
    case allergies = 2
    case symptoms = 3
    case medications = 4
    case memory = 5
    case complete = 6

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .healthConditions: return "Health Conditions"
        case .allergies: return "Allergies"
        case .symptoms: return "Symptoms"
        case .medications: return "Medications"
        case .memory: return "Privacy"
        case .complete: return "Complete"
        }
    }

    var progress: Double {
        Double(rawValue + 1) / Double(OnboardingStep.allCases.count)
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep

    var body: some View {
        VStack(spacing: 8) {
            // Step indicators
            HStack(spacing: 4) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Rectangle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .clipShape(Capsule())
                }
            }

            // Step label
            Text("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count): \(currentStep.title)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Helper Model for Onboarding

struct OnboardingAllergy: Identifiable {
    let id = UUID()
    var name: String
    var type: AllergyType
    var severity: AllergySeverity
    var crossReactiveItems: [String]
}

// MARK: - Preview

#Preview {
    OnboardingContainerView(onComplete: {})
        .modelContainer(for: [UserProfile.self, UserAllergy.self], inMemory: true)
}
