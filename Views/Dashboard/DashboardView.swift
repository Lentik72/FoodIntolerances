import SwiftUI
import SwiftData
import Charts
import Combine

enum ActiveSheet: Identifiable {
    case avoidList
    var id: Int { hashValue }
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var tabManager: TabManager
    @State private var activeSheet: ActiveSheet?
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var viewModel = LogItemViewModel()
    @Query(sort: [SortDescriptor(\LogEntry.date, order: .reverse)])
    private var allLogs: [LogEntry]

    @Query(filter: #Predicate<TherapyProtocol> { $0.isActive }, sort: [SortDescriptor(\TherapyProtocol.dateAdded, order: .reverse)])
    private var activeProtocols: [TherapyProtocol]

    // AI-related queries
    @Query(sort: \AIMemory.confidence, order: .reverse) private var aiMemories: [AIMemory]
    @Query private var userProfiles: [UserProfile]
    @Query private var userAllergies: [UserAllergy]
    @Query private var healthScreenings: [HealthScreeningSchedule]
    
    @State private var isRefreshing = false
    @State private var showRefreshConfirmation = false
    @State private var refreshTrigger = false
    @State private var lastUpdated: Date? = nil
    @State private var hasInitializedEnvironmentalData = false
    
    private var refreshDebouncer: AnyCancellable?
    private let refreshDebounceInterval: TimeInterval = 2.0 // seconds
    
    var sortedLogs: [LogEntry] {
        allLogs.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                    
                    if let locationManager = viewModel.locationManager,
                       locationManager.currentLocation == nil {
                        ZStack {
                            VStack {
                                Text("Location Access Needed")
                                    .font(.headline)
                                    .padding(.bottom, 2)
                                
                                Text("Enable location access to get accurate environmental data")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                Button(action: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Text("Open Settings")
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .padding(.top, 8)
                                .accessibilityLabel("Open Settings")
                                .accessibilityHint("Double tap to open device settings and enable location access")
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(radius: 5)
                        }
                        .padding()
                    }
                    
                    if isRefreshing {
                        VStack {
                            ProgressView("Refreshing Data...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .padding()
                            Text("Fetching the latest updates...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 4)
                        .padding()
                    }
                    
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // MARK: - Zone A: Today at a glance
                        AIInsightsSummaryCard(
                            logs: allLogs,
                            memories: aiMemories,
                            userAllergies: userAllergies,
                            profile: userProfiles.first,
                            screenings: healthScreenings,
                            environmentalPressure: viewModel.atmosphericPressureCategory
                        )

                        // MARK: - Zone B: Quick Actions
                        QuickSymptomLogger(viewModel: viewModel)

                        // MARK: - Zone C: Recent Activity
                        EnhancedRecentLogsCard(logs: allLogs)

                        // Upcoming reminders (only if any exist)
                        if !activeProtocols.filter({ $0.enableReminder && $0.reminderTime != nil }).isEmpty {
                            UpcomingRemindersCard(protocols: activeProtocols, isRefreshing: $isRefreshing, showRefreshConfirmation: $showRefreshConfirmation)
                        }

                        // Quick tools row (scrollable for flexibility)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                QuickToolButton(icon: "questionmark.circle", label: "Can I Eat?", color: .purple) {
                                    // Navigate to FoodQueryView
                                }
                                QuickToolButton(icon: "hand.raised.fill", label: "Avoid List", color: .red) {
                                    activeSheet = .avoidList
                                }
                                QuickToolButton(icon: "bell.fill", label: "Reminders", color: .orange) {
                                    tabManager.selectedTab = .more
                                }
                                QuickToolButton(icon: "chart.bar.fill", label: "Trends", color: .blue) {
                                    tabManager.selectedTab = .trends
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .id(refreshTrigger ? "refresh-on" : "refresh-off")
                    .onChange(of: showRefreshConfirmation) { oldValue, newValue in
                        if newValue {
                            // Prevent cascading updates by using a slight delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            }
                        }
                    }
                    .onChange(of: refreshTrigger) { oldValue, newValue in
                    }
                    .onReceive(viewModel.$lastUpdated) { newDate in
                        
                        let shouldUpdate = !showRefreshConfirmation
                        if shouldUpdate {
                            
                            withAnimation {
                                showRefreshConfirmation = true
                                refreshTrigger.toggle()
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation {
                                    showRefreshConfirmation = false
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await refreshDashboard()
                }
                
                // Subtle refresh confirmation (bottom toast)
                if showRefreshConfirmation {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Updated")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .onAppear {
                            if !hasInitializedEnvironmentalData {
                                Task {
                                    await viewModel.fetchAllData()
                                    hasInitializedEnvironmentalData = true
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut(duration: 0.3), value: showRefreshConfirmation)
                    }
                    .padding(.bottom, 100)
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Home")

            .onAppear {
                       // Activate location for dashboard
                       viewModel.locationManager?.setDashboardActive(true)

                       // Check proactive alerts on dashboard appear
                       checkProactiveAlerts()
                   }
                   .onDisappear {
                       // Suspend location updates when dashboard not visible
                       viewModel.locationManager?.setDashboardActive(false)
                   }
                   .onChange(of: viewModel.atmosphericPressureCategory) { oldValue, newValue in
                       // Check environmental alerts when pressure changes
                       if oldValue != newValue && !newValue.contains("Loading") {
                           checkEnvironmentalAlerts(pressure: newValue)
                       }
                   }
            
            // ✅ **Listen for Navigation Event from LogSymptomView**
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NavigateToDashboard"))) { _ in
                DispatchQueue.main.async {
                    tabManager.selectedTab = .dashboard // Ensure Dashboard is shown
                }
            }
    }
    
    private func fetchLogsManually() -> [LogEntry] {
        do {
            let descriptor = FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\LogEntry.date, order: .reverse)])
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.error(error, message: "Error fetching logs manually", category: .data)
            return []
        }
    }
      
    // MARK: - Proactive Alerts

    private func checkProactiveAlerts() {
        let alertService = ProactiveAlertService.shared

        // Schedule screening reminders
        if alertService.enableScreeningReminders {
            alertService.scheduleScreeningReminders(screenings: healthScreenings)
        }

        // Check clinical escalations
        if alertService.enableDoctorRecommendations {
            alertService.checkClinicalEscalations(logs: allLogs)
        }

        // Schedule morning wellness check
        alertService.scheduleMorningWellnessCheck(
            memories: aiMemories,
            screenings: healthScreenings,
            environmentalPressure: viewModel.atmosphericPressureCategory,
            hour: alertService.morningWellnessCheckHour,
            minute: alertService.morningWellnessCheckMinute
        )

        // Check supplement reminders based on recent patterns
        if alertService.enableSupplementReminders {
            alertService.scheduleSupplementReminders(
                memories: aiMemories,
                recentLogs: allLogs
            )
        }
    }

    private func checkEnvironmentalAlerts(pressure: String) {
        let alertService = ProactiveAlertService.shared

        guard alertService.enableEnvironmentalAlerts else { return }

        alertService.checkEnvironmentalConditions(
            pressure: pressure,
            memories: aiMemories
        ) { alertSent in
            if alertSent {
                Logger.info("Environmental alert sent for pressure: \(pressure)", category: .notification)
            }
        }
    }

    // ✅ Optimized Refresh Function
    private func refreshDashboard() async {

        // Show refresh indicator with animation
        await MainActor.run {
            withAnimation {
                isRefreshing = true
            }
        }
        
        // Use the environmental service directly - with cooldown
        let success = await viewModel.environmentalService.requestRefreshWithCooldown()
        
        // Final UI updates
        await MainActor.run {
            lastUpdated = Date() // Update timestamp
            
            // Use a withAnimation block for smooth transitions
            withAnimation(.easeInOut(duration: 0.5)) {
                isRefreshing = false
                
                // Only show confirmation if refresh succeeded
                if success {
                    showRefreshConfirmation = true
                    refreshTrigger.toggle() // Force UI refresh
                    viewModel.lastUpdated = Date()
                }
            }
            
            // Auto-hide the confirmation after a delay
            if showRefreshConfirmation {
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation {
                        showRefreshConfirmation = false
                    }
                }
            }
        }
        
    }
}

// 🌟 Daily Summary Card
struct DailySummaryCard: View {
    let logs: [LogEntry]
    @ObservedObject var viewModel: LogItemViewModel
    
    var todayLogs: [LogEntry] {
        logs.filter { Calendar.current.isDateInToday($0.date) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("📊 Today's Summary")
                .font(.headline)
            
            HStack(spacing: 20) {
                // ✅ Logs Today Section
                VStack {
                    Text("\(todayLogs.count)")
                        .font(.largeTitle)
                        .bold()
                    Text("Logs Today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // ✅ Atmospheric Pressure Section
                VStack {
                    Text(viewModel.atmosphericPressureCategory)
                        .font(.title2)
                        .foregroundColor(viewModel.atmosphericPressureCategory == "High" ? .red : (viewModel.atmosphericPressureCategory == "Low" ? .blue : .green))
                    Text("Atmospheric Pressure")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // ✅ Moon Phase Image Section
                VStack {
                    Image(systemName: moonPhaseIcon(for: viewModel.autoMoonPhase))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.yellow)
                    
                    Text(viewModel.autoMoonPhase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
        .shadow(radius: 3)
        .padding(.horizontal)
    }
    
    // ✅ Moon Phase Icon Mapper
    func moonPhaseIcon(for phase: String) -> String {
        switch phase.lowercased() {
        case "new moon": return "moon.circle.fill"
        case "waxing crescent": return "moon.fill"
        case "first quarter": return "moon.first.quarter.fill"
        case "waxing gibbous": return "moonphase.waxing.gibbous"
        case "full moon": return "moon.circle"
        case "waning gibbous": return "moonphase.waning.gibbous"
        case "last quarter": return "moon.last.quarter.fill"
        case "waning crescent": return "moon"
        default: return "moon.stars.fill"
        }
    }
}
             
// 🌟 Environmental Triggers Card
struct EnvironmentalFactorsCard: View {
    @ObservedObject var viewModel: LogItemViewModel
    
    // Add this to force view updates when these properties change
    @State private var forceRefreshTrigger = false
    
    // Trigger Conditions
    var isSuddenAtmosphericPressureChange: Bool { viewModel.suddenPressureChange }
    var pressureTrend: String { viewModel.pressureTrend }
    var isFullMoonApproaching: Bool { viewModel.autoMoonPhase.lowercased().contains("waxing gibbous") }
    var isNewMoonApproaching: Bool { viewModel.autoMoonPhase.lowercased().contains("waning crescent") }
    var isMercuryRetrogradeApproaching: Bool { viewModel.isMercuryRetrogradeApproaching(for: viewModel.date) }
    var isCurrentlyInRetrograde: Bool { viewModel.isMercuryInRetrograde(for: viewModel.date) }
    
    // Trigger Lists
    var suddenChangeTriggers: [String] {
        isSuddenAtmosphericPressureChange ? ["Headaches", "Dizziness", "Fatigue"] : []
    }
    var fullMoonTriggers: [String] {
        isFullMoonApproaching ? ["Insomnia", "Restlessness", "Mood Changes"] : []
    }
    var newMoonTriggers: [String] {
        isNewMoonApproaching ? ["Fatigue", "Mood Changes", "Sleep Disturbances", "Digestive Issues", "Headaches"] : []
    }
    var mercuryTriggers: [String] {
        if isCurrentlyInRetrograde {
            return ["Cognitive Fog", "Mood Swings", "Communication Issues"]
        } else if isMercuryRetrogradeApproaching {
            return ["Prepare for Tech Glitches", "Double-Check Communications"]
        }
        return []
    }
    
    private func pressureTriggers(for category: String) -> [String] {
        switch category {
        case "High":
            return ["Headaches", "Nosebleeds", "Joint Pain", "Fatigue"]
        case "Low":
            return ["Dizziness", "Shortness of Breath", "Nausea", "Fatigue"]
        case "Normal":
            return ["Stable Conditions, No Common Triggers"]
        default:
            return []
        }
    }
    
    func getMoonPhaseSymptoms(for phase: String) -> [String] {
        switch phase.lowercased() {
        case _ where phase.lowercased().contains("waning gibbous"):
            return ["Energy Decrease", "Emotional Release", "Physical Tiredness", "Digestive Sensitivity"]
        case _ where phase.lowercased().contains("waxing gibbous"):
            return ["Rising Energy", "Heightened Emotions", "Sleep Changes", "Headaches"]
        case _ where phase.lowercased().contains("full moon"):
            return ["Insomnia", "Increased Sensitivity", "Heightened Emotions", "Headaches"]
        case _ where phase.lowercased().contains("new moon"):
            return ["Low Energy", "Introversion", "Digestive Changes", "Need for Rest"]
        case _ where phase.lowercased().contains("first quarter"):
            return ["Energy Increase", "Emotional Intensity", "Physical Vitality"]
        case _ where phase.lowercased().contains("last quarter"):
            return ["Energy Decline", "Need for Rest", "Emotional Release"]
        case _ where phase.lowercased().contains("waxing crescent"):
            return ["Gradual Energy Rise", "Mild Sensitivity", "Starting New Cycles"]
        case _ where phase.lowercased().contains("waning crescent"):
            return ["Fatigue", "Need for Rest", "Digestive Sensitivity", "Emotional Release"]
        default:
            return []
        }
    }
    func daysUntilNextFullMoon() -> Int? {
        let calendar = Calendar.current
        let today = Date()
        
        // Check next 30 days
        for dayOffset in 1...30 {
            guard let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            
            // Use your existing getMoonPhase function
            let moonPhaseOnDate = getMoonPhase(for: futureDate)
            
            // Check if this date has a full moon - adjust the string to match your implementation
            if moonPhaseOnDate.contains("Full Moon 🌕") {
                return dayOffset
            }
        }
        
        return nil
    }

    // Uses global getMoonPhase(for:) from GetMoonPhase.swift

    func getPressureColor(_ category: String) -> Color {
        switch category {
        case "High": return .red
        case "Low": return .blue
        case "Normal": return .green
        default: return .gray
        }
    }
    
    func getTrendIndicator(for category: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: category == "High" ? "arrow.up.circle.fill" :
                    category == "Low" ? "arrow.down.circle.fill" : "circle.fill")
            .foregroundColor(getPressureColor(category))
            Text(category)
                .font(.caption)
                .bold()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🌍 Environmental Factors")
                .font(.headline)
                .padding(.bottom, 5)
            
            HStack(spacing: 15) {
                StatusIndicator(
                    title: "Pressure",
                    value: viewModel.atmosphericPressureCategory,
                    color: getPressureColor(viewModel.atmosphericPressureCategory)
                )
                Divider().frame(height: 30)
                StatusIndicator(
                    title: "Moon",
                    value: viewModel.autoMoonPhase,
                    color: .purple
                )
                Divider().frame(height: 30)
                StatusIndicator(
                    title: "Mercury",
                    value: isCurrentlyInRetrograde ? "Retrograde" : "Direct",
                    color: isCurrentlyInRetrograde ? .orange : .green
                )
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            
            // Add this after the title
            if viewModel.atmosphericPressureCategory.contains("Loading") {
                HStack {
                    ProgressView()
                        .padding(.trailing, 5)
                    Text("Updating environmental data...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 5)
            }
            
            // Immediate Alerts Section
            if isSuddenAtmosphericPressureChange || isFullMoonApproaching || isNewMoonApproaching || isMercuryRetrogradeApproaching {
                VStack(spacing: 8) {
                    if isSuddenAtmosphericPressureChange {
                        TriggerSection(
                            title: "⚡ Sudden Pressure Change \(pressureTrend)",
                            triggers: suddenChangeTriggers,
                            color: .red,
                            isWarning: true,
                            backgroundGradient: LinearGradient(colors: [.red.opacity(0.8), .pink.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        )
                    }
                    
                    if isFullMoonApproaching {
                        let daysLeft = daysUntilNextFullMoon() ?? 0
                        if daysLeft > 0 { // Only show if days is positive
                            TriggerSection(
                                title: "🌕 Full Moon Approaching - \(daysLeft) day\(daysLeft == 1 ? "" : "s")",
                                triggers: fullMoonTriggers,
                                color: .yellow,
                                isWarning: true,
                                backgroundGradient: LinearGradient(colors: [.yellow.opacity(0.8), .orange.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                            )
                        }
                    }
                    
                    if isNewMoonApproaching {
                        TriggerSection(
                            title: "🌑 New Moon Approaching",
                            triggers: newMoonTriggers,
                            color: .purple,
                            isWarning: true,
                            backgroundGradient: LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        )
                    }
                    
                    if isMercuryRetrogradeApproaching {
                        TriggerSection(
                            title: "☿ Mercury Retrograde Approaching",
                            triggers: mercuryTriggers,
                            color: .orange,
                            isWarning: true,
                            backgroundGradient: LinearGradient(colors: [.orange.opacity(0.8), .red.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        )
                    }
                }
                Divider().padding(.vertical, 5)
            }
            
            // Ongoing Mercury Status Section
            if !isMercuryRetrogradeApproaching && !isCurrentlyInRetrograde {
                TriggerSection(
                    title: "☿ Mercury Retrograde Status",
                    triggers: ["Not in Retrograde"],
                    color: .green
                )
            } else if isCurrentlyInRetrograde {
                TriggerSection(
                    title: "☿ Mercury is in Retrograde",
                    triggers: mercuryTriggers,
                    color: .orange
                )
            }
            
            // Moon Phase Section (shown only once)
            if !viewModel.autoMoonPhase.isEmpty {
                TriggerSection(
                    title: "🌙 Moon Phase: \(viewModel.autoMoonPhase)",
                    triggers: getMoonPhaseSymptoms(for: viewModel.autoMoonPhase),
                    color: .purple
                )
            }
            
            // Atmospheric Pressure Section (only if no sudden change)
            if !isSuddenAtmosphericPressureChange {
                if viewModel.atmosphericPressureCategory.contains("Error") || 
                   viewModel.atmosphericPressureCategory.contains("Loading") ||
                   viewModel.atmosphericPressureCategory.contains("Location") {
                    TriggerSection(
                        title: "🌬️ Atmospheric Pressure",
                        triggers: [viewModel.atmosphericPressureCategory],
                        color: .orange,
                        isWarning: true,
                        backgroundGradient: LinearGradient(colors: [.orange.opacity(0.8), .red.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    )
                    Button("Retry") {
                        Task {
                            if let locationManager = viewModel.locationManager {
                                locationManager.requestLocationUpdate()
                            }
                            await viewModel.fetchAtmosphericPressure()
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                } else {
                    TriggerSection(
                        title: viewModel.atmosphericPressureCategory != "Unknown" && !viewModel.atmosphericPressureCategory.isEmpty
                        ? "🌬️ Atmospheric Pressure: \(viewModel.atmosphericPressureCategory)"
                        : "🌬️ Atmospheric Pressure: Data Unavailable",
                        triggers: pressureTriggers(for: viewModel.atmosphericPressureCategory),
                        color: .blue
                    )
                }
            }
            
            // Add debug timestamp
            Text("Last updated: \(viewModel.lastUpdated.formatted(date: .numeric, time: .standard))")
                .font(.caption2)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
        .shadow(radius: 3)
        .padding(.horizontal)
        .overlay(
            Group {
                if viewModel.atmosphericPressureCategory.contains("Loading") {
                    ZStack {
                        Color.black.opacity(0.1)
                        ProgressView()
                            .scaleEffect(1.5)
                    }
                }
            }
        )
        .refreshable {  // Add this modifier
            viewModel.refreshEnvironmentalData()
        }
        .onChange(of: viewModel.lastUpdated) { oldValue, newValue in
            // Force view to refresh when data updates
            forceRefreshTrigger.toggle()
        }
        .id("env-card-\(forceRefreshTrigger)") // This forces SwiftUI to recreate the view
    }
}

struct StatusIndicator: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .bold()
                .foregroundColor(color)
        }
    }
}

        // 🌟 Reusable Trigger Section
        struct TriggerSection: View {
            let title: String
            let triggers: [String]
            let color: Color
            var isWarning: Bool = false
            var backgroundGradient: LinearGradient? = nil
            
            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if isWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(color)
                        }
                        Text(title)
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(isWarning ? .black : color)
                            .shadow(color: isWarning ? .gray.opacity(0.5) : .clear, radius: 1, x: 0, y: 1)
                            .lineLimit(1)
                    }
                    
                    if !triggers.isEmpty {
                        Text(triggers.joined(separator: " • "))  // Changed from " / " to " • "
                            .font(.caption)
                            .foregroundColor(Color.primary)
                            .padding(.leading, isWarning ? 24 : 0)
                            .lineSpacing(4)  // Added for better readability
                    }
                }
                .padding(.vertical, 8)  // Reduced padding
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    backgroundGradient != nil ? AnyView(backgroundGradient!) : AnyView(Color(.tertiarySystemBackground))
                )
                .cornerRadius(12)
            }
        }
        // 🌟 Recent Logs Card
        struct EnhancedRecentLogsCard: View {
            let logs: [LogEntry]
            @State private var selectedLog: LogEntry?
            @State private var showEditSheet = false
            
            var recentLogs: [LogEntry] {
                Array(logs.prefix(5))
            }
            
            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Logs")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    if recentLogs.isEmpty {
                        Text("No recent logs available.")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(recentLogs, id: \.id) { log in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(log.severity >= 4 ? Color.red : (log.severity >= 2 ? Color.yellow : Color.green))
                                    .frame(width: 14, height: 14)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.itemName)
                                        .font(.headline)
                                    Text("Logged on \(log.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                
                                Button(action: {
                                    selectedLog = log
                                    showEditSheet = true
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .accessibilityLabel("Edit log")
                                .accessibilityHint("Double tap to edit this log entry")
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground)) // ✅ Updated to match other cards
                            .cornerRadius(12)
                            .shadow(radius: 2)
                            .onTapGesture {
                                selectedLog = log
                                showEditSheet = true
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(log.itemName), logged on \(log.date.formatted(date: .abbreviated, time: .shortened)), severity \(log.severity)")
                            .accessibilityHint("Double tap to edit")
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground)) // ✅ Consistent with other cards
                .cornerRadius(15)
                .shadow(radius: 3)
                .padding(.horizontal)
                .sheet(item: $selectedLog) { log in
                    EditLogSheet(log: log) // Ensure EditLogSheet exists
                }
            }
        }
        
        // 🌟 Enhanced Symptom Trends Card
        struct SymptomTrendsCard: View {
            let logs: [LogEntry]
            @EnvironmentObject var tabManager: TabManager
            @State private var selectedSymptom: String? = nil
            
            var mostCommonSymptoms: [String] {
                let allSymptoms = logs.flatMap { $0.symptoms }
                let symptomCounts = Dictionary(grouping: allSymptoms, by: { $0 }).mapValues { $0.count }
                return symptomCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
            }
            
            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top 3 Most Common Symptoms")
                        .font(.headline)
                    
                    if mostCommonSymptoms.isEmpty {
                        VStack {
                            Text("No symptom trends yet. Start logging to see trends!")
                                .foregroundColor(.gray)
                            Button(action: {
                                tabManager.selectedTab = .logs
                            }) {
                                Text("Log Now")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                    } else {
                        ForEach(mostCommonSymptoms, id: \.self) { symptom in
                            HStack {
                                Text(symptom)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                let count = logs.filter { $0.symptoms.contains(symptom) }.count
                                Text("\(count) times")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle()) // Makes the entire row tappable
                            .onTapGesture {
                                selectedSymptom = symptom
                                tabManager.selectedTab = .logs
                                NotificationCenter.default.post(name: .filterBySymptom, object: symptom)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(15)
                .shadow(radius: 3)
                .padding(.horizontal)
            }
        }
        // 🌟 Symptom Detail View
        struct SymptomDetailView: View {
            let symptom: String
            let logs: [LogEntry]
            
            var symptomLogs: [LogEntry] {
                logs.filter { $0.symptoms.contains(symptom) }
            }
            
            var body: some View {
                NavigationStack {
                    List(symptomLogs, id: \.id) { log in
                        VStack(alignment: .leading) {
                            Text(log.itemName)
                                .font(.headline)
                            Text("Logged on \(log.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Severity: \(log.severity)")
                                .font(.caption)
                                .foregroundColor(log.severity >= 4 ? .red : (log.severity >= 2 ? .yellow : .green))
                        }
                    }
                    .navigationTitle("\(symptom) Details")
                }
            }
        }
        // 🌟 Protocol Adherence Tracker
        struct ProtocolAdherenceTracker: View {
            let protocols: [TherapyProtocol]
            
            var adherenceRate: Double {
                let allItems = protocols.flatMap { $0.items }
                let completedItems = allItems.filter { $0.isCompleted }
                return allItems.isEmpty ? 0 : (Double(completedItems.count) / Double(allItems.count)) * 100
            }
            
            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Protocol Adherence")
                        .font(.headline)
                    
                    ProgressView(value: adherenceRate, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    
                    Text("\(Int(adherenceRate))% adherence")
                        .foregroundColor(adherenceRate > 75 ? .green : .red)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(15)
                .shadow(radius: 3)
                .padding(.horizontal)
            }
        }
        
        // 🌟 Upcoming Reminders Card
        struct UpcomingRemindersCard: View {
            let protocols: [TherapyProtocol]
            @Binding var isRefreshing: Bool
            @Binding var showRefreshConfirmation: Bool
            @State private var showAllReminders = false
            
            var upcomingReminders: [TherapyProtocol] {
                protocols.filter { $0.enableReminder && $0.reminderTime != nil }
            }
            
            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Upcoming Reminders")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    if upcomingReminders.isEmpty {
                        Text("No upcoming reminders.")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(upcomingReminders.prefix(3), id: \.id) { proto in
                            HStack {
                                Text(proto.title)
                                Spacer()
                                if let reminderTime = proto.reminderTime {
                                    Text(reminderTime, style: .time)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        
                        // ✅ Button to Trigger Refresh
                        Button("Refresh Reminders") {
                            refreshReminders()
                        }
                        .padding(.top, 5)
                        .foregroundColor(.blue)
                        
                        if upcomingReminders.count > 3 {
                            Button("View All Reminders") {
                                showAllReminders.toggle()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(15)
                .shadow(radius: 3)
                .padding(.horizontal)
                .sheet(isPresented: $showAllReminders) {
                    RemindersView()
                }
            }
            
            // ✅ Moved Refresh Logic to a Function
            private func refreshReminders() {
                isRefreshing = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { // Simulate async work
                    isRefreshing = false
                    showRefreshConfirmation = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showRefreshConfirmation = false
                        }
                    }
                }
            }
        }
        // 🌟 Utility Icon Button
        struct UtilityIconButton: View {
            let icon: String
            let label: String
            let color: Color
            let action: () -> Void

            var body: some View {
                VStack(spacing: 4) {
                    Button(action: action) {
                        ZStack {
                            Circle()
                                .fill(color)
                                .frame(width: 60, height: 60)
                                .shadow(radius: 4)

                            Image(systemName: icon)
                                .foregroundColor(.white)
                                .font(.system(size: 24, weight: .bold))
                        }
                    }
                    .accessibilityLabel(label)
                    .accessibilityHint("Double tap to open \(label)")
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
        }

struct PersonalizedInsightsCard: View {
    let logs: [LogEntry]
    @EnvironmentObject var tabManager: TabManager
    
    var recentLogs: [LogEntry] {
        return logs.filter { Calendar.current.isDateInThisWeek($0.date) }
    }
    
    var symptomCounts: [(symptom: String, count: Int)] {
        let allSymptoms = recentLogs.flatMap { $0.symptoms }
        let counts = Dictionary(grouping: allSymptoms, by: { $0 })
            .mapValues { $0.count }
            .filter { $0.value > 1 }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }
    
    var hasHeadacheWithLowPressure: Bool {
        return recentLogs.contains { (log: LogEntry) in
            log.symptoms.contains("Headache") && log.atmosphericPressure == "Low"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💡 Personal Insights")
                .font(.headline)
                .padding(.bottom, 5)
            
            if symptomCounts.isEmpty {
                Text("Keep logging to see personalized insights!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    // Top symptom insight
                    if let topSymptom = symptomCounts.first {
                        InsightCard(
                            title: "Symptom Pattern",
                            message: "You logged \(topSymptom.count) instances of \(topSymptom.symptom) this week.",
                            actionLabel: "Analyze",
                            iconName: "magnifyingglass.circle.fill",
                            color: .blue
                        ) {
                            tabManager.selectedTab = .trends
                            NotificationCenter.default.post(name: .filterBySymptom, object: topSymptom.symptom)
                        }
                    }
                    
                    // Weather correlation insight
                    if hasHeadacheWithLowPressure {
                        InsightCard(
                            title: "Environmental Correlation",
                            message: "Your headaches may be linked to low atmospheric pressure.",
                            actionLabel: "Learn More",
                            iconName: "cloud.fill",
                            color: .purple
                        ) {
                            // Navigate to educational content
                        }
                    }
                    
                    // Recent activity insight
                    if !recentLogs.isEmpty {
                        let daysSinceLastLog = Calendar.current.dateComponents([.day], from: recentLogs[0].date, to: Date()).day ?? 0
                        
                        if daysSinceLastLog > 2 {
                            InsightCard(
                                title: "Logging Reminder",
                                message: "It's been \(daysSinceLastLog) days since your last log. Regular tracking improves insights.",
                                actionLabel: "Log Now",
                                iconName: "pencil.circle.fill",
                                color: .green
                            ) {
                                tabManager.selectedTab = .logs
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
        .shadow(radius: 3)
        .padding(.horizontal)
    }
}

struct InsightCard: View {
    var title: String
    var message: String
    var actionLabel: String
    var iconName: String
    var color: Color
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
            }

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(3)

            Button(action: action) {
                Text(actionLabel)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(color)
                    .cornerRadius(8)
            }
            .padding(.top, 4)
            .accessibilityLabel(actionLabel)
            .accessibilityHint("Double tap to \(actionLabel.lowercased())")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(message)")
    }
}

// Add this extension to Calendar
extension Calendar {
    func isDateInThisWeek(_ date: Date) -> Bool {
        return self.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}
// Add this class outside your DashboardView struct
class RefreshController {
    private var refreshDebouncer: AnyCancellable?
    private let refreshDebounceInterval: TimeInterval = 2.0
    private weak var viewModel: LogItemViewModel?
    
    init(viewModel: LogItemViewModel) {
        self.viewModel = viewModel
    }
    
    func debouncedRefresh(isRefreshing: Bool, refreshAction: @escaping () async -> Void) {
        // Cancel existing debouncer
        refreshDebouncer?.cancel()

        if isRefreshing {
            return
        }

        // Create new debounce timer
        refreshDebouncer = Just(())
            .delay(for: .seconds(refreshDebounceInterval), scheduler: RunLoop.main)
            .sink { _ in
                Task {
                    await refreshAction()
                }
            }
    }
}

// MARK: - AI Insights Summary Card (Refactored with Primary/Secondary Hierarchy)

struct AIInsightsSummaryCard: View {
    let logs: [LogEntry]
    let memories: [AIMemory]
    let userAllergies: [UserAllergy]
    let profile: UserProfile?
    let screenings: [HealthScreeningSchedule]
    let environmentalPressure: String

    // One-time dismissible hint
    @AppStorage("hasSeenAIExplanation") private var hasSeenAIExplanation = false

    private var isNewUser: Bool {
        logs.count < 3
    }

    private var totalInsightCount: Int {
        var count = 0
        if primaryInsight != nil { count += 1 }
        count += secondaryInsights.count
        return count
    }

    private var activeMemories: [AIMemory] {
        memories.filter { $0.isActive }
    }

    private var recentTriggers: [AIMemory] {
        activeMemories.filter { $0.memoryTypeEnum == .trigger && $0.confidenceLevel == .high }
    }

    private var whatWorkedMemories: [AIMemory] {
        activeMemories.filter { $0.memoryTypeEnum == .whatWorked && $0.effectivenessScore > 0.6 }
    }

    private var overdueScreenings: [HealthScreeningSchedule] {
        screenings.filter { $0.isEnabled && $0.isOverdue }
    }

    private var hasEnvironmentalWarning: Bool {
        guard environmentalPressure.lowercased() == "low" else { return false }
        return activeMemories.contains { memory in
            memory.memoryTypeEnum == .trigger &&
            (memory.trigger?.lowercased().contains("pressure") == true ||
             memory.symptom?.lowercased().contains("headache") == true ||
             memory.symptom?.lowercased().contains("migraine") == true)
        }
    }

    // MARK: - Insight Priority System
    // Priority: 1. Screening overdue, 2. Environmental risk, 3. Known trigger, 4. What works

    private var primaryInsight: InsightData? {
        // Screening overdue is highest priority (clinical importance)
        if let screening = overdueScreenings.first {
            return InsightData(
                icon: "heart.text.square",
                iconColor: .red,
                title: "Screening Due",
                subtitle: "You may want to schedule your \(screening.screeningName)",
                badge: "Health",
                isPrimary: true
            )
        }

        // Environmental warning for today
        if hasEnvironmentalWarning {
            return InsightData(
                icon: "cloud.fill",
                iconColor: .blue,
                title: "Low Pressure Today",
                subtitle: "This may trigger symptoms based on your history",
                badge: "Today",
                isPrimary: true
            )
        }

        // High-confidence trigger
        if let trigger = recentTriggers.first {
            return InsightData(
                icon: "exclamationmark.triangle",
                iconColor: .orange,
                title: "Known Trigger",
                subtitle: "\(trigger.trigger ?? "Unknown") often precedes \(trigger.symptom ?? "symptoms") (\(trigger.occurrenceCount) times)",
                badge: "High",
                isPrimary: true
            )
        }

        // What works (only if no risks)
        if let remedy = whatWorkedMemories.first {
            return InsightData(
                icon: "checkmark.circle",
                iconColor: .green,
                title: "What Works",
                subtitle: "\(remedy.resolution ?? "Remedy") helps with \(remedy.symptom ?? "symptoms") (\(remedy.effectivenessPercentage)%)",
                badge: "\(remedy.occurrenceCount)×",
                isPrimary: true
            )
        }

        return nil
    }

    private var secondaryInsights: [InsightData] {
        var insights: [InsightData] = []
        var usedTypes: Set<String> = []

        // Mark primary insight type as used
        if let primary = primaryInsight {
            usedTypes.insert(primary.title)
        }

        // Add remaining insights (max 2)
        if !usedTypes.contains("Screening Due"), let screening = overdueScreenings.first {
            insights.append(InsightData(
                icon: "heart.text.square",
                iconColor: .red,
                title: "Screening Due",
                subtitle: "\(screening.screeningName)",
                badge: nil,
                isPrimary: false
            ))
            usedTypes.insert("Screening Due")
        }

        if insights.count < 2, !usedTypes.contains("Low Pressure Today"), hasEnvironmentalWarning {
            insights.append(InsightData(
                icon: "cloud.fill",
                iconColor: .blue,
                title: "Low Pressure",
                subtitle: "May trigger symptoms",
                badge: nil,
                isPrimary: false
            ))
            usedTypes.insert("Low Pressure Today")
        }

        if insights.count < 2, !usedTypes.contains("Known Trigger"), let trigger = recentTriggers.first {
            insights.append(InsightData(
                icon: "exclamationmark.triangle",
                iconColor: .orange,
                title: "Trigger",
                subtitle: "\(trigger.trigger ?? "Unknown") → \(trigger.symptom ?? "symptoms")",
                badge: nil,
                isPrimary: false
            ))
        }

        if insights.count < 2, !usedTypes.contains("What Works"), let remedy = whatWorkedMemories.first {
            insights.append(InsightData(
                icon: "checkmark.circle",
                iconColor: .green.opacity(0.8),
                title: "Helpful",
                subtitle: "\(remedy.resolution ?? "Remedy")",
                badge: nil,
                isPrimary: false
            ))
        }

        return Array(insights.prefix(2))
    }

    private var aiModeLabel: String {
        profile?.aiSuggestionLevelEnum.displayName ?? "Standard"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with AI mode indicator
            HStack(alignment: .center) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Health Assistant")
                        .font(.headline)
                    Text("Today at a glance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Only show "View All" if there are 3+ insights to avoid empty detail screens
                if totalInsightCount >= 3 {
                    NavigationLink(destination: AIInsightsView()) {
                        Text("View All")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            if let primary = primaryInsight {
                // Primary insight (larger, more prominent)
                PrimaryInsightRow(insight: primary)

                // Secondary insights (smaller, muted)
                if !secondaryInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(secondaryInsights, id: \.title) { insight in
                            SecondaryInsightRow(insight: insight)
                        }
                    }
                }
            } else {
                // Empty state with reassurance
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    VStack(spacing: 4) {
                        Text("Nothing concerning detected")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("Log how you're feeling and I'll learn what matters to you")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    // CTA hint for new users
                    if isNewUser {
                        Text("Tap + to log how you feel")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            // One-time "What I Do" hint (dismissible)
            if !hasSeenAIExplanation {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("I look for patterns in your logs and flag things that may matter — nothing diagnostic.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        withAnimation {
                            hasSeenAIExplanation = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .frame(minHeight: 160) // Lock minimum height to prevent jitter
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Insight Data Model

private struct InsightData {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String?
    let isPrimary: Bool
}

// MARK: - Primary Insight Row (Larger, prominent)

private struct PrimaryInsightRow: View {
    let insight: InsightData

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .foregroundColor(insight.iconColor)
                .font(.title2)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let badge = insight.badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(insight.iconColor.opacity(0.8))
                            .cornerRadius(10)
                    }
                }

                Text(insight.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Secondary Insight Row (Smaller, muted)

private struct SecondaryInsightRow: View {
    let insight: InsightData

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: insight.icon)
                .foregroundColor(insight.iconColor.opacity(0.7))
                .font(.caption)
                .frame(width: 16)

            Text(insight.title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("·")
                .foregroundColor(.secondary)

            Text(insight.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
    }
}

struct AIInsightRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badgeText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let badge = badgeText {
                        Text(badge)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Tool Button (Compact)

struct QuickToolButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 80)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }
}
