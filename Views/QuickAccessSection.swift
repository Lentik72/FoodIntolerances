import SwiftUI

// 🌟 Quick Access Section
struct QuickAccessSection: View {
    @EnvironmentObject var tabManager: TabManager
    @State private var showLogSymptomView = false
    @State private var showAddTrackedItemView = false
    @State private var showQuickNoteView = false
    @State private var showRemindersView = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Access")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    quickAccessButton(icon: "pencil", label: "Log Symptom", color: .blue) {
                        showLogSymptomView.toggle()
                    }
                    
                    quickAccessButton(icon: "leaf.fill", label: "Add Item", color: .green) {
                        showAddTrackedItemView.toggle()
                    }
                    
                    quickAccessButton(icon: "note.text", label: "Quick Note", color: .orange) {
                        showQuickNoteView.toggle()
                    }
                    
                    quickAccessButton(icon: "bell.fill", label: "Reminders", color: .purple) {
                        showRemindersView.toggle()
                    }
                    
                    quickAccessButton(icon: "chart.xyaxis.line", label: "Trends", color: .indigo) {
                        tabManager.selectedTab = .trends
                    }
                    
                    quickAccessButton(icon: "book.fill", label: "Protocols", color: .teal) {
                        tabManager.selectedTab = .protocols
                    }
                }
                .padding(.horizontal)
            }
            // Add padding at the bottom for a nicer look
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
        .shadow(radius: 3)
        .padding(.horizontal)
        .sheet(isPresented: $showLogSymptomView) {
            LogSymptomView()
        }
        .sheet(isPresented: $showAddTrackedItemView) {
            AddTrackedItemView()
        }
        .sheet(isPresented: $showQuickNoteView) {
            QuickNoteView()
        }
        .sheet(isPresented: $showRemindersView) {
            RemindersView()
        }
    }

    private func quickAccessButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 50, height: 50) // Slightly smaller
                        .shadow(radius: 2) // Subtle shadow
                    Image(systemName: icon)
                        .foregroundColor(.white)
                        .font(.system(size: 22, weight: .bold)) // Slightly smaller icons
                }
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}
