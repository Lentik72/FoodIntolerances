import SwiftUI
import SwiftData

extension Notification.Name {
    static let filterBySymptom = Notification.Name("filterBySymptom")
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: LogItemViewModel
    @EnvironmentObject var tabManager: TabManager

    // Query for user profile to check onboarding status
    @Query private var userProfiles: [UserProfile]

    @State private var showFABMenu = false
    @State private var showLogSymptomView = false
    @State private var showAddTrackedItemView = false
    @State private var showQuickNoteView = false
    @State private var showPhotoUploadView = false
    @State private var showNotificationSettings = false
    @State private var showAvoidList = false
    @State private var showProtocolTags = false
    @State private var showOnboarding = false

    // Check if onboarding is needed
    private var needsOnboarding: Bool {
        guard let profile = userProfiles.first else { return true }
        return !profile.hasCompletedOnboarding
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TabView(selection: $tabManager.selectedTab) {
                    DashboardView()
                        .tabItem { Label("Dashboard", systemImage: "house.fill") }
                        .tag(TabManager.Tab.dashboard)
                    
                    TrendsAnalysisPage()
                        .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
                        .tag(TabManager.Tab.trends)
                    
                    TrackedItemsView()
                        .tabItem { Label("Foods", systemImage: "leaf.fill") }
                        .tag(TabManager.Tab.foods)
                    
                    LogsView()
                        .tabItem { Label("Log", systemImage: "doc.text.fill") }
                        .tag(TabManager.Tab.logs)
                    
                    MoreView()
                        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                        .tag(TabManager.Tab.more)
                }
                .onAppear {
                    NotificationCenter.default.addObserver(forName: Notification.Name("NavigateToDashboard"), object: nil, queue: .main) { _ in
                        Logger.debug("Navigating to Dashboard...", category: .ui)
                        DispatchQueue.main.async {
                            tabManager.selectedTab = .dashboard
                            Logger.debug("Tab changed to Dashboard: \(tabManager.selectedTab)", category: .ui)
                        }
                    }
                }
                
                // ✅ Floating Action Button (FAB)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingAddButton(showMenu: $showFABMenu, actions: [
                            FABAction(label: "Log Symptom", icon: "pencil", color: .blue) {
                                showLogSymptomView.toggle()
                            },
                            FABAction(label: "Add Tracked Item", icon: "leaf.fill", color: .green) {
                                showAddTrackedItemView.toggle()
                            },
                            FABAction(label: "Quick Note", icon: "note.text", color: .orange) {
                                showQuickNoteView.toggle()
                            },
                            FABAction(label: "Upload/Take Photo", icon: "camera.fill", color: .purple) {
                                showPhotoUploadView.toggle()
                            }
                        ])
                        .padding()
                    }
                }
            }
        }
        .sheet(isPresented: $showLogSymptomView) {
            LogSymptomView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showAddTrackedItemView) {
            AddTrackedItemView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showQuickNoteView) {
            QuickNoteView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showPhotoUploadView) {
            PhotoUploadView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsView()
        }
        .sheet(isPresented: $showAvoidList) {
            AvoidListView()
        }
        .sheet(isPresented: $showProtocolTags) {
            ProtocolTagsView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingContainerView {
                showOnboarding = false
                Logger.info("Onboarding completed", category: .app)
            }
        }
        .onAppear {
            // Check if onboarding is needed on first launch
            if needsOnboarding {
                showOnboarding = true
            }
        }
    }
}

// ✅ Preview
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(LogItemViewModel())
            .environmentObject(TabManager())
            .modelContainer(for: [LogEntry.self, TrackedItem.self, AvoidedItem.self], inMemory: true)
    }
}
