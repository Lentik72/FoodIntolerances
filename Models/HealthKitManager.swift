import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var sleepData: [SleepSample] = []

    init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        
        healthStore.requestAuthorization(toShare: nil, read: [sleepType]) { success, error in
            if success {
                self.fetchSleepData()
            } else if let error = error {
                print("Authorization error: \(error.localizedDescription)")
            }
        }
    }

    func fetchSleepData() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: [])

        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { query, results, error in
            guard let samples = results as? [HKCategorySample] else { return }

            let filteredSamples = samples.filter { sample in
                let hour = Calendar.current.component(.hour, from: sample.startDate)
                return hour >= 20 || hour < 10  // Only sleep between 8 PM and 10 AM
            }

            DispatchQueue.main.async {
                self.sleepData = filteredSamples.map { SleepSample(startDate: $0.startDate, endDate: $0.endDate) }
            }
        }
        healthStore.execute(query)
    }
}

struct SleepSample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    
    var durationInHours: Double {
        return endDate.timeIntervalSince(startDate) / 3600
    }
}
