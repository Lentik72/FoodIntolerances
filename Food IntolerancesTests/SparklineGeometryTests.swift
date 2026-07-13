import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

struct SparklineGeometryTests {
    @Test func mapsTimeOfDayToXAndSeverityToInvertedY() {
        let dayStart = Date(timeIntervalSince1970: 1_750_032_000)
        let noon = dayStart.addingTimeInterval(12 * 3600)
        let points = [
            SeverityPoint(time: dayStart, value: 0),     // x=0, y=bottom
            SeverityPoint(time: noon, value: 5),          // x=mid, y=middle
            SeverityPoint(time: dayStart.addingTimeInterval(86_400), value: 10), // x=end, y=top
        ]
        let mapped = SparklineGeometry.points(for: points, dayStart: dayStart,
                                              in: CGSize(width: 100, height: 20))
        #expect(mapped[0] == CGPoint(x: 0, y: 20))
        #expect(mapped[1] == CGPoint(x: 50, y: 10))
        #expect(mapped[2] == CGPoint(x: 100, y: 0))
    }

    @Test func clampsOutOfDayTimesIntoBounds() {
        let dayStart = Date(timeIntervalSince1970: 1_750_032_000)
        let after = SeverityPoint(time: dayStart.addingTimeInterval(90_000), value: 12)
        let mapped = SparklineGeometry.points(for: [after], dayStart: dayStart,
                                              in: CGSize(width: 100, height: 20))
        #expect(mapped[0].x == 100)   // clamped to day end
        #expect(mapped[0].y == 0)     // clamped to max severity
    }
}
