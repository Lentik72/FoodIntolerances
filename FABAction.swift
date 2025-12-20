import SwiftUI

struct FABAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let color: Color
    let handler: () -> Void
}

struct FloatingAddButton: View {
    @Binding var showMenu: Bool
    var actions: [FABAction]
    @EnvironmentObject var tabManager: TabManager

    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var showQuickAction = false

    private var fabColor: Color {
        switch tabManager.selectedTab {
        case .dashboard: return .blue
        case .logs: return .purple
        case .protocols: return .green
        case .cabinet: return .orange
        default: return .gray
        }
    }

    var body: some View {
        ZStack {
            if showMenu {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation {
                            showMenu = false
                        }
                    }

                ForEach(actions.indices, id: \.self) { index in
                    let angle = Double(index) * (360.0 / Double(actions.count))
                    let radius: CGFloat = 100

                    Button(action: {
                        withAnimation {
                            showMenu = false
                            actions[index].handler()
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: actions[index].icon)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(actions[index].color))
                                .shadow(radius: 5)

                            Text(actions[index].label)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(6)
                        }
                    }
                    .accessibilityLabel(actions[index].label)
                    .accessibilityHint("Double tap to \(actions[index].label.lowercased())")
                    .offset(x: CGFloat(cos(angle * .pi / 180)) * radius,
                            y: CGFloat(sin(angle * .pi / 180)) * radius)
                    .transition(.scale)
                }
            }

            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    if !isDragging && !showQuickAction {
                        showMenu.toggle()
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(fabColor)
                        .frame(width: 50, height: 50)
                        .shadow(color: .gray.opacity(0.4), radius: 3, x: 1, y: 1)

                    Image(systemName: showMenu ? "xmark" : "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(showMenu ? 180 : 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showMenu)
                }
            }
            .accessibilityLabel(showMenu ? "Close menu" : "Add new item")
            .accessibilityHint(showMenu ? "Double tap to close the action menu" : "Double tap to open quick actions menu")
            .padding()
            .offset(dragOffset)
            .offset(y: -10)
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        withAnimation {
                            isDragging = true
                        }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            if isDragging {
                                dragOffset = value.translation
                            }
                        }
                        .onEnded { _ in
                            withAnimation {
                                snapToEdge()
                                isDragging = false
                            }
                        }
                    )
            )
            .onLongPressGesture(minimumDuration: 1.5) {
                if let quickAction = actions.first {
                    quickAction.handler()
                    showQuickAction = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showQuickAction = false
                    }
                }
            }
        }
    }

    private func snapToEdge() {
        let screenWidth = UIScreen.main.bounds.width
        if dragOffset.width > screenWidth / 4 {
            dragOffset.width = screenWidth / 2 - 50
        } else if dragOffset.width < -screenWidth / 4 {
            dragOffset.width = -screenWidth / 2 + 50
        } else {
            dragOffset.width = 0
        }
    }
}
