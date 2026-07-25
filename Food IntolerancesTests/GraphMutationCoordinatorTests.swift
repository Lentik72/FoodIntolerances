import Testing
@testable import Food_Intolerances

@MainActor
@Suite struct GraphMutationCoordinatorTests {
    @Test func graphMutatedIncrementsRevision() {
        let c = GraphMutationCoordinator()
        #expect(c.revision == 0)
        c.graphMutated()
        #expect(c.revision == 1)
        c.graphMutated()
        #expect(c.revision == 2)
    }
}
