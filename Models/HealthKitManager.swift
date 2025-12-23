import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var sleepData: [SleepSample] = []
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined

    enum AuthorizationStatus {
        case notDetermined
        case authorized
        case denied
        case unavailable
    }

    /// Whether HealthKit is available on this device
    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init() {
        // Don't request authorization automatically - let UI trigger it
        updateAuthorizationStatus()
    }

    /// Update the current authorization status
    private func updateAuthorizationStatus() {
        guard Self.isAvailable else {
            authorizationStatus = .unavailable
            return
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            authorizationStatus = .unavailable
            return
        }

        let status = healthStore.authorizationStatus(for: sleepType)
        DispatchQueue.main.async {
            switch status {
            case .notDetermined:
                self.authorizationStatus = .notDetermined
            case .sharingAuthorized:
                self.authorizationStatus = .authorized
            case .sharingDenied:
                self.authorizationStatus = .denied
            @unknown default:
                self.authorizationStatus = .notDetermined
            }
        }
    }

    /// Request HealthKit authorization - call this from UI action, not automatically
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard Self.isAvailable else {
            authorizationStatus = .unavailable
            completion?(false)
            return
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            Logger.warning("Sleep analysis type not available", category: .health)
            authorizationStatus = .unavailable
            completion?(false)
            return
        }

        healthStore.requestAuthorization(toShare: nil, read: [sleepType]) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.authorizationStatus = .authorized
                    self?.fetchSleepData()
                } else {
                    self?.authorizationStatus = .denied
                    if let error = error {
                        Logger.error(error, message: "HealthKit authorization error", category: .health)
                    }
                }
                completion?(success)
            }
        }
    }

    /// Fetch sleep data from HealthKit
    func fetchSleepData() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return
        }

        let startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: [])

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, results, error in
            if let error = error {
                Logger.error(error, message: "Failed to fetch sleep data", category: .health)
                return
            }

            guard let samples = results as? [HKCategorySample] else { return }

            let filteredSamples = samples.filter { sample in
                let hour = Calendar.current.component(.hour, from: sample.startDate)
                return hour >= 20 || hour < 10  // Only sleep between 8 PM and 10 AM
            }

            DispatchQueue.main.async {
                self?.sleepData = filteredSamples.map {
                    SleepSample(startDate: $0.startDate, endDate: $0.endDate)
                }
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
