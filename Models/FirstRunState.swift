import Foundation
import HealthGraphCore

enum FirstRunKeys {
    static let startedVersion = "hg.firstRun.startedVersion"
    static let completedVersion = "hg.firstRun.completedVersion"
    static let symptomSeeds = "hg.firstRun.symptomSeeds"
    static let forceShow = "hg.firstRun.forceShow"
}

enum FirstRunEntry: Equatable {
    case fresh
    case resume
    case upgrade(from: Int)
}

enum FirstRunResolution: Equatable {
    case shell
    case reconcileThenShell
    case flow(FirstRunEntry)
}

/// Pure launch resolution. Every comparison is against `currentVersion`, never
/// against zero — `completedVersion > 0 -> shell` would make the versioning
/// decorative, sending a v1-completed user straight past a v2 screen.
///
/// Graph existence and the backfill flag arrive as INPUTS and are consulted
/// only in the both-zero row: onboarding itself writes events, so consulting
/// them any later lets onboarding's own writes decide that onboarding is
/// unnecessary.
enum FirstRunResolver {
    static func resolve(defaults: UserDefaults,
                        currentVersion: Int,
                        anyEventExists: () -> Bool,
                        backfillAttempted: Bool) -> FirstRunResolution {
        #if DEBUG
        if defaults.bool(forKey: FirstRunKeys.forceShow) { return .flow(.fresh) }
        #endif
        let started = defaults.integer(forKey: FirstRunKeys.startedVersion)
        let completed = defaults.integer(forKey: FirstRunKeys.completedVersion)

        if completed >= currentVersion { return .shell }
        if started == currentVersion { return .flow(.resume) }
        if completed > 0 { return .flow(.upgrade(from: completed)) }
        if started == 0 && (backfillAttempted || anyEventExists()) { return .reconcileThenShell }
        return .flow(.fresh)
    }
}

/// Owns the persisted first-run markers. Resolution happens once, synchronously,
/// before the first frame — a `@Query`-driven or async gate renders the wrong
/// branch first and flashes.
@MainActor
final class FirstRunState: ObservableObject {
    /// Bump when a round ADDS a screen, and extend the entry mapping with it.
    static let currentVersion = 1

    @Published private(set) var resolution: FirstRunResolution
    private let defaults: UserDefaults

    /// `backfillAttempted` is an explicit dependency with NO default — the
    /// ingestor writes its flag to `.standard`, not to whatever suite this
    /// state was injected with. Reading it off `defaults` here lined up only
    /// because production happens to use `.standard` for both, and would break
    /// silently the day an App Group suite is adopted. The caller decides where
    /// the flag lives.
    init(defaults: UserDefaults = .standard, store: GRDBEventStore, backfillAttempted: Bool) {
        self.defaults = defaults
        // FAIL CLOSED: a read error is a bootstrap failure, not "show
        // onboarding". Onboarding over a populated graph is unrecoverable.
        let exists: () -> Bool = {
            do { return try store.anyEventExistsSync(includingDeleted: true) }
            catch { fatalError("first-run: graph existence check failed: \(error)") }
        }
        let resolved = FirstRunResolver.resolve(
            defaults: defaults,
            currentVersion: Self.currentVersion,
            anyEventExists: exists,
            backfillAttempted: backfillAttempted)
        if resolved == .reconcileThenShell {
            defaults.set(Self.currentVersion, forKey: FirstRunKeys.completedVersion)
        }
        self.resolution = resolved
    }

    /// The resolved entry, or nil when the shell should mount. Deliberately NOT
    /// a Bool: `.resume` has to reach the flow so an interrupted import can be
    /// recovered rather than silently restarted, and `.upgrade` will need it too.
    var flowEntry: FirstRunEntry? { if case let .flow(entry) = resolution { return entry }; return nil }

    /// Written BEFORE any side effect, so a termination mid-flow resumes.
    func markStarted() {
        defaults.set(Self.currentVersion, forKey: FirstRunKeys.startedVersion)
    }

    func markCompleted(seeds: [String]) {
        defaults.set(SymptomSeeds.validate(seeds, limit: 8), forKey: FirstRunKeys.symptomSeeds)
        defaults.set(Self.currentVersion, forKey: FirstRunKeys.completedVersion)
        defaults.removeObject(forKey: FirstRunKeys.startedVersion)
        defaults.removeObject(forKey: FirstRunKeys.forceShow)
        resolution = .shell
    }

    /// Re-validated on READ: the stored list outlives catalog and red-flag changes.
    var seeds: [String] {
        SymptomSeeds.validate(defaults.stringArray(forKey: FirstRunKeys.symptomSeeds) ?? [], limit: 8)
    }
}
