import SwiftUI
import SwiftData

@main
struct FoodIntolerancesApp: App {
    // Register transformers at the global scope, before app is instantiated
    static let registerTransformers: Void = {
        StringArrayTransformer.register()
        return ()
    }()
    
    @StateObject private var logItemViewModel = LogItemViewModel()
    @StateObject private var environmentalService = EnvironmentalDataService(locationManager: LocationService())
    @StateObject private var tabManager = TabManager()
    @StateObject private var healthKitManager = HealthKitManager()
    @AppStorage("enableDiagnostics") private var enableDiagnostics = false
    @AppStorage("debugMode") private var debugMode = false

    init() {
        // Ensure transformers are registered before any other code runs
        _ = FoodIntolerancesApp.registerTransformers
        Logger.info("StringArrayTransformer registered", category: .app)

        NotificationManager.shared.requestNotificationPermission()

        // Initialize proactive alert settings
        ProactiveAlertService.shared.initializeDefaultSettings()

        setupGlobalErrorHandling()
    }
    
    var sharedModelContainer: ModelContainer = {
        // Ensure transformers are registered before container creation
        _ = FoodIntolerancesApp.registerTransformers
        
        let schema = Schema([
            LogEntry.self,
            TrackedItem.self,
            Symptom.self,
            TherapyProtocol.self,
            TherapyProtocolItem.self,
            CabinetItem.self,
            AvoidedItem.self,
            OngoingSymptom.self,
            SymptomCheckIn.self,
            MoodEntry.self,
            ProtocolRequirement.self,
            // AI Assistant Models
            UserProfile.self,
            UserAllergy.self,
            AIMemory.self,
            HealthTestResult.self,
            HealthScreeningSchedule.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Schedule recovery after container is created - static method that doesn't capture self
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                FoodIntolerancesApp.recoverFromSwiftDataErrors(container: container)
            }
            
            return container
        } catch {
            Logger.error(error, message: "Error creating ModelContainer", category: .data)
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            let _ = StringArrayTransformer.register() // Ensure registration happens first
            
            MainTabView()
                .environmentObject(healthKitManager)
                .environmentObject(logItemViewModel)
                .environmentObject(tabManager)
                .modelContainer(for: [
                    LogEntry.self,
                    TrackedItem.self,
                    Symptom.self,
                    TherapyProtocol.self,
                    TherapyProtocolItem.self,
                    CabinetItem.self,
                    AvoidedItem.self,
                    OngoingSymptom.self,
                    SymptomCheckIn.self,
                    MoodEntry.self,
                    ProtocolRequirement.self,
                    // AI Assistant Models
                    UserProfile.self,
                    UserAllergy.self,
                    AIMemory.self,
                    HealthTestResult.self,
                    HealthScreeningSchedule.self
                ])
                .resetSwiftDataCache()
                .onAppear {
                    Logger.debug("App started in DEBUG mode", category: .app)
                    if enableDiagnostics {
                        Logger.debug("Diagnostics mode enabled", category: .app)
                    }
                }
        }
    }

    // Helper to migrate any data
    private func migrateData() {
        if !UserDefaults.standard.bool(forKey: "hasPerformedSymptomMigration") {
            Logger.info("Setting up for data migration on first access", category: .migration)
            UserDefaults.standard.set(true, forKey: "hasPerformedSymptomMigration")
        }
    }
    
    private func setupGlobalErrorHandling() {
        // Set up notification observer for app-wide errors
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppErrorOccurred"),
            object: nil,
            queue: .main
        ) { notification in
            if let error = notification.object as? Error {
                Logger.warning("Global error handler caught: \(error.localizedDescription)", category: .app)

                // Attempt recovery for known error types
                if error.localizedDescription.contains("SwiftData") ||
                   error.localizedDescription.contains("Core Data") {
                    Logger.info("Attempting SwiftData recovery...", category: .data)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        Task { @MainActor in
                            try? self.sharedModelContainer.mainContext.save()
                        }
                    }
                }
            }
        }
    }
    
    // Static method for SwiftData error recovery
    @MainActor
    static func recoverFromSwiftDataErrors(container: ModelContainer) {
        do {
            try container.mainContext.save()
            Logger.info("Successfully recovered SwiftData context", category: .data)
        } catch {
            Logger.warning("SwiftData recovery attempt failed: \(error.localizedDescription)", category: .data)
        }
    }
}
