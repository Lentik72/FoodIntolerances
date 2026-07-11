import SwiftUI

/// The four content tabs of the Health OS shell. Named distinctly from the
/// legacy `Tab` enums (TabEnum.swift, TabManager.Tab) to avoid collisions.
enum HealthOSTab: String, CaseIterable, Identifiable {
    case home, timeline, insights, health

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .timeline: "Timeline"
        case .insights: "Insights"
        case .health: "Health"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .timeline: "list.bullet.rectangle"
        case .insights: "sparkles"
        case .health: "heart.text.square"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .timeline: "list.bullet.rectangle.fill"
        case .insights: "sparkles"
        case .health: "heart.text.square.fill"
        }
    }
}
