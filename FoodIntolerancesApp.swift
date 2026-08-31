import SwiftUI
import SwiftData
import HealthGraphCore

@main
struct FoodIntolerancesApp: App {
    // Register transformers at the global scope, before app is instantiated
    static let registerTransformers: Void = {
        StringArrayTransformer.register()
        return ()
    }()
    
    @StateObject private var logItemViewModel = LogItemViewModel()
    @StateObject private var environmentStatusStore: EnvironmentStatusStore
    @StateObject private var environmentalService: EnvironmentalDataService
    @StateObject private var tabManager = TabManager()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var healthKitIngestor = HealthKitIngestor()
    @StateObject private var captureCoordinator = CaptureCoordinator()
    @StateObject private var graphMutationCoordinator = GraphMutationCoordinator()
    @StateObject private var redFlagMuteStore: RedFlagMuteStore
    @StateObject private var redFlagPresenter: RedFlagPresenter
    @State private var emitCoordinator: EnvironmentEmitCoordinator
    // Touching HealthGraphProvider.shared here opens the SQLite file and runs
    // migrations synchronously (and fatalErrors on failure, by design). That
    // cost is paid at launch either way — the resolver needs the graph-existence
    // answer before the first frame.
    //
    // backfillAttempted is read off .standard HERE because that is where
    // HealthKitIngestor writes it — FirstRunState no longer assumes its own
    // defaults suite holds the ingestor's flag.
    @StateObject private var firstRunState = FirstRunState(
        store: GRDBEventStore(database: HealthGraphProvider.shared),
        backfillAttempted: UserDefaults.standard.bool(forKey: HealthKitIngestor.backfillCompletedKey))
    @StateObject private var importStatus: HealthImportStatusStore
    @StateObject private var locationPermission = LocationPermissionStore()
    @AppStorage("enableDiagnostics") private var enableDiagnostics = false
    @AppStorage("debugMode") private var debugMode = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Ensure transformers are registered before any other code runs
        _ = FoodIntolerancesApp.registerTransformers
        Logger.info("StringArrayTransformer registered", category: .app)

        // Initialize proactive alert settings
        ProactiveAlertService.shared.initializeDefaultSettings()

        // Must be assigned before any instance-method call below (setupGlobalErrorHandling
        // captures self, which requires every stored property to be initialized first).
        let muteStore = RedFlagMuteStore()
        _redFlagMuteStore = StateObject(wrappedValue: muteStore)
        _redFlagPresenter = StateObject(wrappedValue: RedFlagPresenter(muteStore: muteStore))

        let statusStore = EnvironmentStatusStore()
        _environmentStatusStore = StateObject(wrappedValue: statusStore)
        let service = EnvironmentalDataService(locationManager: LocationService(), statusStore: statusStore)
        _environmentalService = StateObject(wrappedValue: service)
        // Captures the SAME service + store the triggers and emitter use. Neither of
        // them holds the coordinator, so there is no retain cycle.
        _emitCoordinator = State(wrappedValue: EnvironmentEmitCoordinator { forced in
            await EnvironmentalEventEmitter.emitIfNeeded(
                service: service, statusStore: statusStore, bypassThrottles: forced)
        })

        // Normalize the LIVE store, then hand that exact instance to the
        // @StateObject. Constructing a throwaway store, normalizing it, and
        // letting the @StateObject build its own would write .interrupted to
        // UserDefaults while the instance the UI actually observes still holds
        // the stale .inProgress it loaded — so the Backfill screen would render
        // (or auto-run) instead of showing the recovery branch. The pairing is
        // pinned by makeNormalizedStore + its exact-instance test. Assigned
        // before setupGlobalErrorHandling(), which captures self and therefore
        // needs every stored property initialized.
        _importStatus = StateObject(wrappedValue: HealthImportStatusStore.makeNormalizedStore())

        setupGlobalErrorHandling()

        // Flash-free: reconcile the measurement preference before the scene renders.
        UnitPreferenceBootstrap.reconcileAtLaunch(container: sharedModelContainer)
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
            
            // A structural switch, not a fullScreenCover: covering would mount
            // the whole four-tab shell underneath onboarding — HomeView would
            // subscribe to EnvironmentalDataService and load against an empty
            // graph, and emitCoordinator.emit would start fetching weather
            // while the user is still on the promise screen. The Group sits
            // INSIDE the modifier chain so both branches see every injection —
            // a first-run view presented from above them crashes at runtime on
            // first @EnvironmentObject access.
            Group {
                if let entry = firstRunState.flowEntry {
                    FirstRunFlowView(entry: entry, importOutcome: importStatus.current.outcome) { seeds in
                        firstRunState.markCompleted(seeds: seeds)
                    }
                } else {
                    HealthOSRootView()
                        // Launch side effects live HERE, on the shell branch only.
                        // As common modifiers on the Group they would run during
                        // onboarding — fetching weather and prompting for location
                        // before the user has been told why.
                        .task {
                            healthKitIngestor.startObserving()
                            // Silent, once per install: rewrites the daily-stat
                            // rows the pre-fix trailing recompute clobbered.
                            await DailyStatRepair.runIfDue {
                                _ = try await healthKitIngestor.reingestDailyStats()
                            }
                        }
                        .task { emitCoordinator.emit(forced: false) }
                        .onChange(of: scenePhase) { _, phase in
                            guard phase == .active else { return }
                            emitCoordinator.emit(forced: false)
                        }
                        .onChange(of: environmentalService.locationRecoveryTick) { _, _ in
                            // A trusted coordinate (re)appeared. Only force a bypass emit when a
                            // live location failure actually exists — this bounds the throttle/
                            // cooldown bypass to real recovery and prevents a fetch storm on every
                            // routine device fix.
                            let hasLiveLocationFailure = environmentStatusStore.statuses.values.contains {
                                $0.liveFailure?.reason == .locationDenied || $0.liveFailure?.reason == .locationUnavailable
                            }
                            guard hasLiveLocationFailure else { return }
                            emitCoordinator.emit(forced: true)
                        }
                }
            }
            .environmentObject(healthKitManager)
            .environmentObject(healthKitIngestor)
            .environmentObject(logItemViewModel)
            .environmentObject(tabManager)
            .environmentObject(captureCoordinator)
            .environmentObject(graphMutationCoordinator)
            .environmentObject(redFlagMuteStore)
            .environmentObject(redFlagPresenter)
            .environmentObject(environmentStatusStore)
            .environmentObject(environmentalService)
            .environmentObject(firstRunState)
            .environmentObject(importStatus)
            .environmentObject(locationPermission)
            .environment(\.emitCoordinator, emitCoordinator)
            .fullScreenCover(item: $redFlagPresenter.pending) { match in
                switch match.category {
                case .medicalEmergency:
                    RedFlagInterstitialView(match: match)
                        .environmentObject(redFlagPresenter)   // insurance vs env-inheritance edge cases
                case .mentalHealthCrisis:
                    CrisisSupportView()
                        .environmentObject(redFlagPresenter)
                }
            }
            .modelContainer(sharedModelContainer)
            .resetSwiftDataCache()
            .onAppear {
                Logger.debug("App started in DEBUG mode", category: .app)
                if enableDiagnostics {
                    Logger.debug("Diagnostics mode enabled", category: .app)
                }
                // Wired here (not at HealthKitIngestor construction, which
                // predates the container) so a granted HealthKit
                // authorization — first-run Connect included — can populate
                // UserProfile.dateOfBirth. Optional on the ingestor and set
                // before any authorization request reaches the user.
                healthKitIngestor.modelContainer = sharedModelContainer
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
