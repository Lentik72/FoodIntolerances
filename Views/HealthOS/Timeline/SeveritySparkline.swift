import SwiftUI
import HealthGraphCore

enum SparklineGeometry {
    /// Maps severity points into view coordinates: x = fraction of the 24h day,
    /// y = severity 0–10 inverted (10 at the top). Out-of-range inputs clamp.
    static func points(for points: [SeverityPoint], dayStart: Date, in size: CGSize) -> [CGPoint] {
        points.map { p in
            let dayFraction = min(max(p.time.timeIntervalSince(dayStart) / 86_400, 0), 1)
            let severityFraction = min(max(p.value / 10, 0), 1)
            return CGPoint(x: size.width * dayFraction,
                           y: size.height * (1 - severityFraction))
        }
    }
}

/// Inline per-day severity trend. Renders only for days with >= 2 rated
/// symptom events; the accessibility label carries the actual numbers.
struct SeveritySparkline: View {
    let day: TimelineDay

    var body: some View {
        if day.severityPoints.count >= 2 {
            Canvas { context, size in
                let pts = SparklineGeometry.points(for: day.severityPoints,
                                                   dayStart: day.dayStart, in: size)
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                let color = CategoryFamily.symptoms.color
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3,
                                                        width: 6, height: 6)),
                                 with: .color(color))
                }
            }
            .frame(width: 64, height: 16)
            .accessibilityLabel(summary)
        }
    }

    private var summary: String {
        let values = day.severityPoints.map(\.value)
        let peak = values.max() ?? 0
        return "\(values.count) rated symptoms, severity \(Int(values.min() ?? 0)) to \(Int(peak))"
    }
}
