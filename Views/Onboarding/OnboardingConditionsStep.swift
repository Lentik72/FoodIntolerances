import SwiftUI

/// Step 2: Health conditions
struct OnboardingConditionsStep: View {
    @Binding var selectedConditions: Set<String>

    var onNext: () -> Void
    var onBack: () -> Void

    @State private var customCondition: String = ""
    @State private var showAddCustom: Bool = false

    let commonConditions = CommonHealthCondition.all

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)

                    Text("Health Conditions")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Do you have any ongoing health conditions? This helps me provide relevant screening reminders.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                // Conditions list
                VStack(spacing: 8) {
                    ForEach(commonConditions, id: \.self) { condition in
                        ConditionToggleRow(
                            condition: condition,
                            isSelected: selectedConditions.contains(condition)
                        ) {
                            if selectedConditions.contains(condition) {
                                selectedConditions.remove(condition)
                            } else {
                                selectedConditions.insert(condition)
                            }
                        }
                    }

                    // None option
                    Button(action: {
                        selectedConditions.removeAll()
                    }) {
                        HStack {
                            Image(systemName: selectedConditions.isEmpty ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedConditions.isEmpty ? .blue : .gray.opacity(0.5))
                            Text("None of these")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedConditions.isEmpty ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                    }

                    // Add custom
                    if showAddCustom {
                        HStack {
                            TextField("Enter condition", text: $customCondition)
                                .textFieldStyle(.roundedBorder)

                            Button(action: {
                                if !customCondition.isEmpty {
                                    selectedConditions.insert(customCondition)
                                    customCondition = ""
                                    showAddCustom = false
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        Button(action: { showAddCustom = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Add other condition")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            )
                        }
                    }
                }
                .padding(.horizontal)

                // Selected count
                if !selectedConditions.isEmpty {
                    Text("\(selectedConditions.count) condition\(selectedConditions.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 40)

                // Navigation buttons
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }

                    Button(action: onNext) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
}

struct ConditionToggleRow: View {
    let condition: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                Text(condition)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
        }
    }
}

#Preview {
    OnboardingConditionsStep(
        selectedConditions: .constant(["Diabetes"]),
        onNext: {},
        onBack: {}
    )
}
