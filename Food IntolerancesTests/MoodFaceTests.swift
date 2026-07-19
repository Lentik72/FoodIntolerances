import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct MoodFaceTests {
    @Test func smileDirectionMatchesLevel() {
        #expect(MoodFace(level: .rough).smile < 0)   // frown
        #expect(MoodFace(level: .okay).smile == 0)    // flat
        #expect(MoodFace(level: .good).smile > 0)    // smile
    }
}
