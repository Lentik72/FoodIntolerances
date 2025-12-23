import SwiftUI
import SwiftData

/// "Can I eat X?" interface for checking food safety
struct FoodQueryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \UserAllergy.name) private var userAllergies: [UserAllergy]
    @Query(filter: #Predicate<AIMemory> { $0.memoryType == "trigger" })
    private var learnedTriggers: [AIMemory]

    @State private var searchText: String = ""
    @State private var result: FoodSafetyResult?
    @State private var recentSearches: [String] = []
    @State private var isSearching = false

    private let foodSafetyService = FoodSafetyService()

    // Common foods for quick access
    private let quickFoods = [
        "Apples", "Carrots", "Pineapple", "Shrimp", "Milk",
        "Bread", "Eggs", "Peanuts", "Cheese", "Tomatoes"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Search Header
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)

                        Text("Can I Eat This?")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Check any food against your allergies and sensitivities")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)

                        TextField("Enter a food (e.g., pineapple, shrimp)", text: $searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .onSubmit {
                                performSearch()
                            }

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                result = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Search Button
                    Button(action: performSearch) {
                        HStack {
                            if isSearching {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.shield")
                            }
                            Text("Check Food")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(searchText.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(searchText.isEmpty || isSearching)
                    .padding(.horizontal)

                    // Result Card
                    if let result = result {
                        FoodSafetyResultCard(result: result)
                            .padding(.horizontal)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Quick Foods
                    if result == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick Check")
                                .font(.headline)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(quickFoods, id: \.self) { food in
                                        Button(action: {
                                            searchText = food
                                            performSearch()
                                        }) {
                                            Text(food)
                                                .font(.subheadline)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundColor(.blue)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Recent Searches
                    if !recentSearches.isEmpty && result == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Searches")
                                    .font(.headline)
                                Spacer()
                                Button("Clear") {
                                    recentSearches.removeAll()
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)

                            ForEach(recentSearches.prefix(5), id: \.self) { search in
                                Button(action: {
                                    searchText = search
                                    performSearch()
                                }) {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.secondary)
                                        Text(search)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(8)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Allergy Summary
                    if userAllergies.isEmpty {
                        NoAllergiesCard()
                            .padding(.horizontal)
                    } else if result == nil {
                        AllergySummaryCard(allergies: userAllergies)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Food Safety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .animation(.easeInOut, value: result?.id)
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearching = true

        // Simulate brief delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                result = foodSafetyService.checkFood(
                    searchText,
                    userAllergies: userAllergies,
                    learnedTriggers: learnedTriggers
                )

                // Add to recent searches
                if !recentSearches.contains(searchText) {
                    recentSearches.insert(searchText, at: 0)
                    if recentSearches.count > 10 {
                        recentSearches.removeLast()
                    }
                }

                isSearching = false
            }
        }
    }
}

// MARK: - Food Safety Result Card

struct FoodSafetyResultCard: View {
    let result: FoodSafetyResult

    var body: some View {
        VStack(spacing: 16) {
            // Status Header
            HStack {
                Image(systemName: result.statusIcon)
                    .font(.system(size: 40))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.foodName.capitalized)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(statusColor)
                }

                Spacer()
            }

            Divider()

            // Explanation
            Text(result.explanation)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Cross-reaction source
            if let source = result.crossReactionSource {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(.orange)
                    Text("Cross-reaction with: \(source)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Additional Notes
            if !result.additionalNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.additionalNotes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text(note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }

            // Action Buttons for caution/avoid
            if result.status != .safe {
                HStack(spacing: 12) {
                    if result.status == .caution {
                        Button(action: {}) {
                            Text("I'll risk it")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }

                    Button(action: {}) {
                        Text("Thanks, I'll skip")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(statusColor.opacity(0.3), lineWidth: 2)
        )
    }

    private var statusColor: Color {
        switch result.status {
        case .safe: return .green
        case .caution: return .orange
        case .avoid: return .red
        }
    }

    private var backgroundColor: Color {
        switch result.status {
        case .safe: return Color.green.opacity(0.05)
        case .caution: return Color.orange.opacity(0.05)
        case .avoid: return Color.red.opacity(0.05)
        }
    }

    private var statusText: String {
        switch result.status {
        case .safe: return "Safe for you!"
        case .caution: return "Possible cross-reaction"
        case .avoid: return "NOT SAFE - Avoid"
        }
    }
}

// MARK: - Supporting Views

struct NoAllergiesCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.title2)
                .foregroundColor(.blue)

            Text("No Allergies Added")
                .font(.headline)

            Text("Add your allergies in your profile to get personalized food safety checks.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            NavigationLink(destination: AllergyManagementView()) {
                Text("Add Allergies")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
}

struct AllergySummaryCard: View {
    let allergies: [UserAllergy]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "allergens")
                    .foregroundColor(.orange)
                Text("Your Allergies (\(allergies.count))")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: AllergyManagementView()) {
                    Text("Edit")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            FlowLayout(spacing: 8) {
                ForEach(allergies.prefix(6)) { allergy in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(severityColor(allergy.severityEnum))
                            .frame(width: 8, height: 8)
                        Text(allergy.name)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                }

                if allergies.count > 6 {
                    Text("+\(allergies.count - 6) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
    }

    private func severityColor(_ severity: AllergySeverity) -> Color {
        switch severity {
        case .mild: return .green
        case .moderate: return .yellow
        case .severe: return .red
        }
    }
}

#Preview {
    FoodQueryView()
        .modelContainer(for: [UserAllergy.self, AIMemory.self], inMemory: true)
}
