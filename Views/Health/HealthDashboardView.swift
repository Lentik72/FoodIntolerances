import SwiftUI
import SwiftData

/// Main health dashboard showing test results, screenings, and recommendations
struct HealthDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HealthTestResult.testDate, order: .reverse) private var testResults: [HealthTestResult]
    @Query(sort: \HealthScreeningSchedule.nextDueDate) private var screenings: [HealthScreeningSchedule]
    @Query private var userProfiles: [UserProfile]
    @Query(sort: \LogEntry.date, order: .reverse) private var logs: [LogEntry]

    @State private var showAddTest = false
    @State private var selectedTab: HealthTab = .overview

    private let healthService = HealthMonitoringService()

    private var profile: UserProfile? { userProfiles.first }

    enum HealthTab: String, CaseIterable {
        case overview = "Overview"
        case tests = "Tests"
        case screenings = "Screenings"

        var icon: String {
            switch self {
            case .overview: return "heart.text.square"
            case .tests: return "testtube.2"
            case .screenings: return "calendar.badge.clock"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Category", selection: $selectedTab) {
                    ForEach(HealthTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .overview:
                    OverviewTabView(
                        testResults: testResults,
                        screenings: screenings,
                        profile: profile,
                        logs: Array(logs.prefix(100)),
                        healthService: healthService
                    )
                case .tests:
                    TestResultsTabView(testResults: testResults)
                case .screenings:
                    ScreeningsTabView(screenings: screenings, profile: profile)
                }
            }
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showAddTest = true
                        } label: {
                            Label("Add Test Result", systemImage: "plus")
                        }

                        Button {
                            setupScreenings()
                        } label: {
                            Label("Refresh Screenings", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddTest) {
                AddHealthTestResultView()
            }
            .onAppear {
                setupScreeningsIfNeeded()
            }
        }
    }

    private func setupScreeningsIfNeeded() {
        if screenings.isEmpty, let profile = profile {
            _ = healthService.setupRecommendedScreenings(for: profile, context: modelContext)
            try? modelContext.save()
        }
    }

    private func setupScreenings() {
        guard let profile = profile else { return }
        _ = healthService.setupRecommendedScreenings(for: profile, context: modelContext)
        try? modelContext.save()
    }
}

// MARK: - Overview Tab

struct OverviewTabView: View {
    let testResults: [HealthTestResult]
    let screenings: [HealthScreeningSchedule]
    let profile: UserProfile?
    let logs: [LogEntry]
    let healthService: HealthMonitoringService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Health Score Card
                HealthScoreCard(summary: healthSummary)

                // Alerts Section
                if !alerts.isEmpty {
                    AlertsSection(alerts: alerts)
                }

                // Recommendations
                if !recommendations.isEmpty {
                    RecommendationsSection(recommendations: recommendations)
                }

                // Quick Stats
                QuickStatsSection(
                    testCount: testResults.count,
                    abnormalCount: testResults.filter { $0.statusEnum != .normal }.count,
                    overdueScreenings: screenings.filter { $0.isOverdue }.count,
                    upcomingScreenings: screenings.filter { $0.isUpcoming }.count
                )
            }
            .padding()
        }
    }

    private var healthSummary: HealthSummary {
        healthService.generateHealthSummary(testResults: testResults, screenings: screenings)
    }

    private var alerts: [HealthConcern] {
        healthService.analyzeTestResults(testResults)
    }

    private var recommendations: [HealthRecommendation] {
        guard let profile = profile else { return [] }
        return healthService.getRecommendations(
            profile: profile,
            testResults: testResults,
            screenings: screenings,
            logs: logs
        )
    }
}

// MARK: - Health Score Card

struct HealthScoreCard: View {
    let summary: HealthSummary

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Health Score")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(summary.scoreDescription)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 70, height: 70)

                    Circle()
                        .trim(from: 0, to: CGFloat(summary.healthScore) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))

                    Text("\(summary.healthScore)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }

            Divider()

            HStack {
                StatItem(value: "\(summary.recentResults.count)", label: "Recent Tests", icon: "testtube.2")
                Spacer()
                StatItem(value: "\(summary.abnormalResultsCount)", label: "Abnormal", icon: "exclamationmark.circle")
                Spacer()
                StatItem(value: "\(summary.overdueScreeningsCount)", label: "Overdue", icon: "clock.badge.exclamationmark")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(16)
    }

    private var scoreColor: Color {
        switch summary.healthScore {
        case 90...100: return .green
        case 75..<90: return .blue
        case 60..<75: return .yellow
        default: return .orange
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Alerts Section

struct AlertsSection: View {
    let alerts: [HealthConcern]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attention Needed")
                .font(.headline)

            ForEach(alerts.prefix(3)) { alert in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: alert.severity.icon)
                        .foregroundColor(alertColor(alert.severity))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(alert.recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(alertColor(alert.severity).opacity(0.1))
                .cornerRadius(10)
            }
        }
    }

    private func alertColor(_ severity: ConcernSeverity) -> Color {
        switch severity {
        case .low: return .yellow
        case .moderate: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Recommendations Section

struct RecommendationsSection: View {
    let recommendations: [HealthRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.headline)

            ForEach(recommendations.prefix(3)) { rec in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(rec.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(rec.actionText)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
        }
    }
}

// MARK: - Quick Stats Section

struct QuickStatsSection: View {
    let testCount: Int
    let abnormalCount: Int
    let overdueScreenings: Int
    let upcomingScreenings: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickStatCard(title: "Test Results", value: "\(testCount)", icon: "testtube.2", color: .blue)
                QuickStatCard(title: "Abnormal", value: "\(abnormalCount)", icon: "exclamationmark.triangle", color: abnormalCount > 0 ? .orange : .green)
                QuickStatCard(title: "Overdue", value: "\(overdueScreenings)", icon: "clock.badge.exclamationmark", color: overdueScreenings > 0 ? .red : .green)
                QuickStatCard(title: "Upcoming", value: "\(upcomingScreenings)", icon: "calendar", color: .purple)
            }
        }
    }
}

struct QuickStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Test Results Tab

struct TestResultsTabView: View {
    let testResults: [HealthTestResult]
    @State private var showAddTest = false

    var body: some View {
        List {
            if testResults.isEmpty {
                ContentUnavailableView(
                    "No Test Results",
                    systemImage: "testtube.2",
                    description: Text("Add your lab results to track your health over time")
                )
            } else {
                ForEach(groupedResults.keys.sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(groupedResults[category] ?? []) { result in
                            TestResultRow(result: result)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var groupedResults: [String: [HealthTestResult]] {
        Dictionary(grouping: testResults, by: { $0.category })
    }
}

struct TestResultRow: View {
    let result: HealthTestResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.testName)
                    .font(.headline)
                Text(result.formattedValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(result.testDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: result.statusIcon)
                    .foregroundColor(statusColor)
                Text(result.statusEnum.rawValue)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch result.statusEnum {
        case .normal: return .green
        case .borderlineLow, .borderlineHigh: return .yellow
        case .low, .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Screenings Tab

struct ScreeningsTabView: View {
    let screenings: [HealthScreeningSchedule]
    let profile: UserProfile?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if screenings.isEmpty {
                ContentUnavailableView(
                    "No Screenings Set Up",
                    systemImage: "calendar.badge.clock",
                    description: Text("Complete your profile to get personalized screening recommendations")
                )
            } else {
                // Overdue
                if !overdueScreenings.isEmpty {
                    Section {
                        ForEach(overdueScreenings) { screening in
                            ScreeningRow(screening: screening, onComplete: { completeScreening(screening) })
                        }
                    } header: {
                        Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }

                // Upcoming
                if !upcomingScreenings.isEmpty {
                    Section("Upcoming (Next 30 Days)") {
                        ForEach(upcomingScreenings) { screening in
                            ScreeningRow(screening: screening, onComplete: { completeScreening(screening) })
                        }
                    }
                }

                // Scheduled
                if !scheduledScreenings.isEmpty {
                    Section("Scheduled") {
                        ForEach(scheduledScreenings) { screening in
                            ScreeningRow(screening: screening, onComplete: { completeScreening(screening) })
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var overdueScreenings: [HealthScreeningSchedule] {
        screenings.filter { $0.isOverdue && $0.isEnabled }
    }

    private var upcomingScreenings: [HealthScreeningSchedule] {
        screenings.filter { $0.isUpcoming && !$0.isOverdue && $0.isEnabled }
    }

    private var scheduledScreenings: [HealthScreeningSchedule] {
        screenings.filter { !$0.isUpcoming && !$0.isOverdue && $0.isEnabled }
    }

    private func completeScreening(_ screening: HealthScreeningSchedule) {
        screening.markCompleted()
        try? modelContext.save()
    }
}

struct ScreeningRow: View {
    let screening: HealthScreeningSchedule
    let onComplete: () -> Void

    @State private var showCompleteConfirm = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(screening.screeningName)
                    .font(.headline)
                Text(screening.frequencyDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let dueDate = screening.nextDueDate {
                    HStack(spacing: 4) {
                        Image(systemName: screening.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                            .font(.caption)
                        Text(screening.isOverdue ? "Overdue" : "Due: \(dueDate, style: .date)")
                            .font(.caption)
                    }
                    .foregroundColor(screening.isOverdue ? .red : .secondary)
                }
            }

            Spacer()

            Button("Done") {
                showCompleteConfirm = true
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.2))
            .foregroundColor(.green)
            .cornerRadius(16)
        }
        .padding(.vertical, 4)
        .confirmationDialog("Mark as Completed?", isPresented: $showCompleteConfirm) {
            Button("Mark Completed") {
                onComplete()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Add Health Test Result View

struct AddHealthTestResultView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTest: CommonHealthTest?
    @State private var customTestName: String = ""
    @State private var value: String = ""
    @State private var unit: String = ""
    @State private var testDate: Date = Date()
    @State private var notes: String = ""
    @State private var labName: String = ""
    @State private var wasFasting: Bool = false

    @State private var showTestPicker = false

    var body: some View {
        NavigationStack {
            Form {
                // Test Selection
                Section("Test Information") {
                    Button {
                        showTestPicker = true
                    } label: {
                        HStack {
                            Text("Select Test")
                            Spacer()
                            Text(selectedTest?.name ?? "Choose...")
                                .foregroundColor(.secondary)
                        }
                    }

                    if selectedTest == nil {
                        TextField("Or enter custom test name", text: $customTestName)
                    }
                }

                // Value
                Section("Result") {
                    TextField("Value", text: $value)
                        .keyboardType(.decimalPad)

                    if let test = selectedTest {
                        HStack {
                            Text("Unit")
                            Spacer()
                            Text(test.unit)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Normal Range")
                            Spacer()
                            Text(test.normalRange)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        TextField("Unit (e.g., mg/dL)", text: $unit)
                    }
                }

                // Date and Context
                Section("Details") {
                    DatePicker("Test Date", selection: $testDate, displayedComponents: .date)

                    TextField("Lab Name (optional)", text: $labName)

                    if selectedTest?.fastingRequired == true {
                        Toggle("Was Fasting", isOn: $wasFasting)
                    }
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle("Add Test Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveResult() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showTestPicker) {
                TestPickerView(selectedTest: $selectedTest)
            }
        }
    }

    private var canSave: Bool {
        !value.isEmpty && (selectedTest != nil || !customTestName.isEmpty)
    }

    private func saveResult() {
        let testName = selectedTest?.name ?? customTestName
        let testUnit = selectedTest?.unit ?? unit
        let normalRange = selectedTest?.normalRange

        let result = HealthTestResult(
            testName: testName,
            category: selectedTest?.category ?? "General",
            value: value,
            unit: testUnit.isEmpty ? nil : testUnit,
            normalRangeText: normalRange,
            normalRangeMin: selectedTest?.normalMin,
            normalRangeMax: selectedTest?.normalMax,
            testDate: testDate,
            notes: notes.isEmpty ? nil : notes,
            labName: labName.isEmpty ? nil : labName
        )

        // Calculate status
        let status = result.calculateStatus()
        result.status = status.rawValue
        result.wasFasting = wasFasting

        modelContext.insert(result)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            Logger.error(error, message: "Failed to save test result", category: .data)
        }
    }
}

// MARK: - Test Picker View

struct TestPickerView: View {
    @Binding var selectedTest: CommonHealthTest?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(CommonHealthTest.byCategory().keys.sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(CommonHealthTest.byCategory()[category] ?? [], id: \.name) { test in
                            Button {
                                selectedTest = test
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(test.name)
                                        .foregroundColor(.primary)
                                    Text("Normal: \(test.normalRange)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    HealthDashboardView()
        .modelContainer(for: [HealthTestResult.self, HealthScreeningSchedule.self, UserProfile.self, LogEntry.self], inMemory: true)
}
