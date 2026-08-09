import Foundation
import Testing
@testable import Food_Intolerances

/// Pins the grid's selection rule as a transition rather than leaving it in a
/// closure inside a Button label, where only a mounted host could reach it.
///
/// The cap is the part worth pinning. "Pick up to eight" has to bound
/// ADDITION only — the obvious spelling, a `guard count < limit` in front of
/// the whole toggle, also blocks REMOVAL, so a user who picks their eighth
/// chip can no longer change their mind about any of them.
@Suite struct SeedSelectionTests {

    @Test func tappingAnUnselectedKeyAppendsItAtTheEnd() {
        // Append order is the user's pick order, and it survives all the way to
        // the chip row: ChipRanker fills leftover slots with seeds IN THE GIVEN
        // ORDER, so sorting here would silently reorder the user's chips.
        #expect(SeedSelection.toggled("c", in: ["a", "b"]) == ["a", "b", "c"])
    }

    @Test func tappingASelectedKeyRemovesIt() {
        #expect(SeedSelection.toggled("b", in: ["a", "b", "c"]) == ["a", "c"])
    }

    @Test func theCapRejectsTheNinthPick() {
        let eight = ["a", "b", "c", "d", "e", "f", "g", "h"]
        #expect(SeedSelection.toggled("i", in: eight) == eight)
    }

    @Test func deselectionStillWorksAtTheCap() {
        // The discriminating case: a cap checked before the whole body leaves a
        // full selection frozen — every tap a no-op, including on chips that
        // are already selected.
        let eight = ["a", "b", "c", "d", "e", "f", "g", "h"]
        #expect(SeedSelection.toggled("d", in: eight) == ["a", "b", "c", "e", "f", "g", "h"])
    }

    @Test func aFreedSlotCanBeRefilled() {
        let eight = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let afterRemoval = SeedSelection.toggled("a", in: eight)
        #expect(SeedSelection.toggled("i", in: afterRemoval).count == 8)
        #expect(SeedSelection.toggled("i", in: afterRemoval).last == "i")
    }

    @Test func theCapMatchesTheLimitSeedValidationEnforces() {
        // SymptomSeeds.validate truncates at 8. A grid that allowed more would
        // let the user pick chips that are silently dropped on save.
        #expect(SeedSelection.limit == 8)
    }
}
