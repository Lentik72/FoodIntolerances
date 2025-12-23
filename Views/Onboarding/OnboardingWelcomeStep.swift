import SwiftUI

/// Step 1: Welcome and basic info (age, gender)
struct OnboardingWelcomeStep: View {
    @Binding var age: Int?
    @Binding var gender: String?

    var onNext: () -> Void

    @State private var ageText: String = ""
    @FocusState private var isAgeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue.gradient)

                    Text("Welcome!")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("I'm your personal health assistant. To give you personalized advice, I need to learn a bit about you.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)

                // Form
                VStack(spacing: 24) {
                    // Age
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Age")
                            .font(.headline)

                        TextField("Enter your age", text: $ageText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($isAgeFocused)
                            .onChange(of: ageText) { _, newValue in
                                // Filter to only numbers
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered != newValue {
                                    ageText = filtered
                                }
                                age = Int(filtered)
                            }

                        Text("This helps me recommend age-appropriate health screenings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Gender
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gender")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(Gender.allCases, id: \.rawValue) { genderOption in
                                Button(action: {
                                    gender = genderOption.rawValue
                                }) {
                                    HStack {
                                        Text(genderOption.rawValue)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if gender == genderOption.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundColor(.gray.opacity(0.5))
                                        }
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(gender == genderOption.rawValue ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                    )
                                }
                            }
                        }

                        Text("Some health screenings are gender-specific")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)

                // Continue button
                Button(action: onNext) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .onTapGesture {
            isAgeFocused = false
        }
        .onAppear {
            if let existingAge = age {
                ageText = String(existingAge)
            }
        }
    }
}

#Preview {
    OnboardingWelcomeStep(
        age: .constant(nil),
        gender: .constant(nil),
        onNext: {}
    )
}
