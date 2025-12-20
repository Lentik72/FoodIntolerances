import SwiftUI

struct PieChartView: View {
    let data: [PieSliceData]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<data.count, id: \.self) { index in
                    PieSlice(
                        startAngle: angle(at: index),
                        endAngle: angle(at: index + 1)
                    )
                    .fill(color(at: index))
                    .overlay(
                        sliceLabel(for: index, in: geometry.size)
                    )
                    .scaleEffect(1.05)
                    .animation(.easeInOut(duration: 1.0), value: data) // Animation applied here
                }
            }
            .rotationEffect(.degrees(-90)) // Start pie chart at the top
        }
    }

    // Calculate the start and end angles for a slice
    private func angle(at index: Int) -> Angle {
        let total = data.reduce(0) { $0 + $1.value }
        let cumulative = data.prefix(index).reduce(0) { $0 + $1.value }
        return Angle(degrees: (cumulative / total) * 360)
    }

    // Generate a label for each slice
    private func sliceLabel(for index: Int, in size: CGSize) -> some View {
        let midAngle = self.midAngle(index: index)
        let offsetX = size.width * 0.3 * cos(midAngle)
        let offsetY = size.height * 0.3 * sin(midAngle)

        return Text(data[index].label)
            .font(.caption)
            .foregroundColor(.white)
            .position(x: size.width / 2 + offsetX,
                      y: size.height / 2 + offsetY)
    }

    // Calculate the midpoint angle of a slice
    private func midAngle(index: Int) -> CGFloat {
        let startAngle = angle(at: index).degrees
        let endAngle = angle(at: index + 1).degrees
        return CGFloat((startAngle + endAngle) / 2) * .pi / 180
    }

    // Cycle through a fixed set of colors
    private func color(at index: Int) -> Color {
        let colors: [Color] = [.red, .green, .blue, .orange, .purple, .pink, .cyan, .indigo]
        return colors[index % colors.count]
    }
}

// MARK: - Supporting Models

struct PieSliceData: Identifiable, Equatable {
    let id = UUID()
    let value: Double
    let label: String
}

struct PieSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}
