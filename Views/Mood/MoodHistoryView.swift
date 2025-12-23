import SwiftUI
import SwiftData
import Charts
import HealthKit

struct MoodHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var healthKitManager: HealthKitManager
    @Query(sort: \MoodEntry.date, order: .reverse, animation: .default)
    private var moodEntries: [MoodEntry]

    @Query(sort: \LogEntry.date, order: .reverse)
    private var logEntries: [LogEntry]

    var body: some View {
        List {
            // 📊 Mood Trends
            Section(header: Text("Mood Trends Over Time").font(.headline)) {
                if !moodEntries.isEmpty {
                    MoodLineChart(moodEntries: moodEntries)
                        .frame(height: 200)
                } else {
                    Text("No mood data available.")
                        .foregroundColor(.gray)
                }
            }

            // 🔗 Mood-Symptom Correlations
            Section(header: Text("Mood-Symptom Correlations").font(.headline)) {
                ForEach(moodEntries, id: \.id) { moodEntry in
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Mood: \(moodEntry.mood)")
                                .font(.headline)
                            Spacer()
                            Text(moodEntry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        let symptoms = logEntries
                            .filter { Calendar.current.isDate($0.date, inSameDayAs: moodEntry.date) }
                            .flatMap { $0.symptoms }

                        if symptoms.isEmpty {
                            Text("No symptoms logged.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Symptoms: \(symptoms.joined(separator: ", "))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }

                        // 🛌 Sleep Data Integration (Previous Night's Sleep Only)
                        // 💤 Correlate with the previous night's sleep
                        // 💤 Improved Night Sleep Filter (8 PM - 10 AM)
                      
                            if let sleepSample = healthKitManager.sleepData.first(where: {
                                let moodDate = Calendar.current.startOfDay(for: moodEntry.date)
                                let sleepEndDate = Calendar.current.startOfDay(for: $0.endDate)
                                return sleepEndDate == moodDate
                            }) {
                                let hoursSlept = sleepSample.endDate.timeIntervalSince(sleepSample.startDate) / 3600
                                Text("🛌 Sleep: \(String(format: "%.1f", hoursSlept)) hours")
                                    .font(.subheadline)
                                    .foregroundColor(.purple)
                            } else {
                            Text("No sleep data for the previous night.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                                }
                    }
                    .padding(.vertical, 6)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteMoodEntry(moodEntry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }

            // 📈 Sleep Trends
            Section(header: Text("Sleep Trends").font(.headline)) {
                if !healthKitManager.sleepData.isEmpty {
                    SleepTrendsChart(sleepData: healthKitManager.sleepData)
                        .frame(height: 200)
                } else {
                    Text("No sleep data available. Connect to Apple Health.")
                        .foregroundColor(.gray)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    // 🚮 Delete Mood Entry
    private func deleteMoodEntry(_ moodEntry: MoodEntry) {
        withAnimation {
            modelContext.delete(moodEntry)
            do {
                try modelContext.save()
            } catch {
                Logger.error(error, message: "Error deleting mood entry", category: .data)
            }
        }
    }

    // 💤 Filter for Night Sleep (8 PM - 10 AM)
    private func previousNightSleep(for date: Date) -> SleepSample? {
        let previousNight = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        return healthKitManager.sleepData.first(where: { sample in
            let startHour = Calendar.current.component(.hour, from: sample.startDate)
            let isNightSleep = (startHour >= 20 || startHour < 10) // Between 8 PM - 10 AM
            return Calendar.current.isDate(sample.startDate, inSameDayAs: previousNight) && isNightSleep
        })
    }
}

// 📈 Mood Line Chart
struct MoodLineChart: View {
    let moodEntries: [MoodEntry]

    private func moodValue(_ mood: String) -> Int {
        switch mood {
        case "😊": return 5
        case "😐": return 3
        case "😔": return 2
        case "😡": return 1
        case "😴": return 4
        default: return 0
        }
    }

    var body: some View {
        Chart {
            ForEach(moodEntries, id: \.id) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Mood", moodValue(entry.mood))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue)
                .symbol(Circle())
            }
        }
    }
}
