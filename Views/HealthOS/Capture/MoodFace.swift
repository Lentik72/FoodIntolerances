import SwiftUI
import HealthGraphCore

/// The single place a mood is drawn. A tinted round face whose mouth curve is
/// driven by the level: frown (Rough) → flat (Okay) → smile (Good). Custom-drawn
/// (not emoji) so it renders identically on every device and tints to the palette.
struct MoodFace: View {
    let level: MoodLevel
    var size: CGFloat = 56

    // `internal` (not `private`) so MoodFaceTests can pin the level→expression mapping.
    var tint: Color {
        switch level {
        case .rough: HealthTheme.moodRough
        case .okay:  HealthTheme.moodOkay
        case .good:  HealthTheme.moodGood
        }
    }
    /// Mouth control-point offset as a fraction of the mouth rect height:
    /// +ve dips the middle down → smile; -ve raises it → frown; 0 → flat.
    var smile: CGFloat {
        switch level {
        case .rough: -0.7
        case .okay:   0
        case .good:   0.7
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16))
            Circle().stroke(tint, lineWidth: size * 0.055)
            HStack(spacing: size * 0.26) {
                Circle().fill(tint).frame(width: size * 0.1, height: size * 0.1)
                Circle().fill(tint).frame(width: size * 0.1, height: size * 0.1)
            }
            .offset(y: -size * 0.12)
            MouthShape(smile: smile)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .frame(width: size * 0.44, height: size * 0.26)
                .offset(y: size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)   // the enclosing button carries the label
    }
}

/// A quadratic mouth curve. `smile` moves the control point vertically as a
/// fraction of height: +ve → smile, 0 → flat line, -ve → frown.
private struct MouthShape: Shape {
    var smile: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.midY + smile * rect.height))
        return p
    }
}

private struct MoodFaceGallery: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(MoodLevel.allCases, id: \.rawValue) { MoodFace(level: $0, size: 76) }
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HealthTheme.paper)
    }
}

#Preview("Light") { MoodFaceGallery().preferredColorScheme(.light) }
#Preview("Dark")  { MoodFaceGallery().preferredColorScheme(.dark) }
