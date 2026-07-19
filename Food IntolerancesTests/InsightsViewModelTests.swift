import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct InsightsViewModelTests {
    func seedMinedDB() async throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), days: 150, seed: 42,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food, outcomeSubtype: "bloating",
                                      lagHours: 8, lagJitterHours: 3, followProbability: 0.8, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...2)).insert(into: db)
        _ = try await EvidenceEngine(database: db).recompute(asOf: Date(timeIntervalSince1970: 1_713_000_000))
        return db
    }

    @Test func loadsActiveDairyBloatingCardWithRecentWindow() async throws {
        let db = try await seedMinedDB()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 1_713_000_000) })
        await vm.load()
        let dairy = vm.feed.sections.first { $0.kind == .active }?.cards
            .first { $0.claim.lowercased().contains("dairy") && $0.claim.contains("bloating") }
        #expect(dairy != nil)
        #expect(dairy?.recentDots.isEmpty == false)        // last-N window loaded (not lifetime totals)
        #expect((dairy?.recentDots.count ?? 99) <= 8)      // capped at recentDotCount
        #expect(dairy?.countLine != nil)                   // "In K of your last N Dairy logs, bloating followed"
    }

    @Test func dismissMovesCardToArchive() async throws {
        let db = try await seedMinedDB()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 1_713_000_000) })
        await vm.load()
        let card = vm.feed.sections.first { $0.kind == .active }!.cards.first!
        await vm.dismiss(card)
        let stillActive = vm.feed.sections.first { $0.kind == .active }?.cards.contains { $0.id == card.id } ?? false
        let inArchive = vm.feed.sections.first { $0.kind == .archive }?.cards.contains { $0.id == card.id } ?? false
        #expect(!stillActive)
        #expect(inArchive)
    }

    @Test func moodEdgeSurfacesWithTentativePhrasing() async throws {
        let refNow = Date(timeIntervalSince1970: 1_713_000_000)
        let db = try AppDatabase.inMemory()
        let mood = Relationship(
            fromCategory: "shortSleep", toCategory: "mood", type: .possibleTrigger,
            evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
            firstSeen: refNow.addingTimeInterval(-5 * 86_400), lastSeen: refNow, lastRecomputed: refNow,
            status: .active, edgeKey: "derived:shortSleep|mood:low|possibleTrigger", toSubtype: "low")
        try await GRDBRelationshipStore(database: db).save(mood)
        let vm = InsightsViewModel(database: db, now: { refNow })
        await vm.load()
        let card = vm.feed.sections.flatMap(\.cards).first { $0.claim.lowercased().contains("mood") }
        #expect(card != nil)                                          // un-suppressed
        #expect(card?.claim == "Short sleep is linked to lower mood") // tentative mood phrasing via the VM
    }

    @Test func undoRestoresDismissedCard() async throws {
        let db = try await seedMinedDB()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 1_713_000_000) })
        await vm.load()
        let card = vm.feed.sections.first { $0.kind == .active }!.cards.first!
        await vm.dismiss(card)
        #expect(vm.pendingUndo?.id == card.id)
        await vm.undoDismiss()
        #expect(vm.feed.sections.first { $0.kind == .active }?.cards.contains { $0.id == card.id } == true)
        #expect(vm.pendingUndo == nil)
    }
}
