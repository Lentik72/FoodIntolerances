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
        print("App initialization - StringArrayTransformer registered")
        
        NotificationManager.shared.requestNotificationPermission()
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
            ProtocolRequirement.self
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
            print("Error creating ModelContainer: \(error)")
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
                    ProtocolRequirement.self
                ])
                .resetSwiftDataCache()
                .onAppear {
                    #if DEBUG
                    print("App started in DEBUG mode")
                    if enableDiagnostics {
                        print("🔍 Diagnostics mode enabled")
                    }
                    #endif
                }
        }
    }

    // Helper to migrate any data
    private func migrateData() {
        if !UserDefaults.standard.bool(forKey: "hasPerformedSymptomMigration") {
            print("Setting up for data migration on first access")
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
                print("⚠️ Global error handler caught: \(error.localizedDescription)")
                
                // Attempt recovery for known error types
                if error.localizedDescription.contains("SwiftData") ||
                   error.localizedDescription.contains("Core Data") {
                    print("🔄 Attempting SwiftData recovery...")
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
            print("✅ Successfully recovered SwiftData context")
        } catch {
            print("⚠️ SwiftData recovery attempt failed: \(error.localizedDescription)")
        }
    }
}
