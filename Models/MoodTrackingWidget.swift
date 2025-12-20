import SwiftUI
import SwiftData

struct MoodTrackingWidget: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMood: String?
    @State private var showMoodConfirmation = false

    let moods = ["😊", "😐", "😔", "😡", "😴"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mood Tracker")
                .font(.headline)

            // 🌟 Mood Buttons
            HStack(spacing: 15) {
                ForEach(moods, id: \.self) { mood in
                    Button(action: {
                        selectedMood = mood
                        saveMood(mood)
                        showMoodConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showMoodConfirmation = false
                        }
                    }) {
                        Text(mood)
                            .font(.largeTitle)
                            .padding(10)
                            .background(selectedMood == mood ? Color.blue.opacity(0.2) : Color.clear)
                            .clipShape(Circle())
                    }
                }
            }

            // ✅ Mood Confirmation
            if showMoodConfirmation {
                Text("Mood saved: \(selectedMood ?? "")")
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            NavigationLink(destination: MoodHistoryView()) {
                Text("📅 View Full Mood History")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.top, 5)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(15)
        .shadow(radius: 3)
        .padding(.horizontal)
    }

    private func saveMood(_ mood: String) {
        let newEntry = MoodEntry(mood: mood)
        modelContext.insert(newEntry)
    }
}
