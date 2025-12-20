// TabManager.swift

import SwiftUI

class TabManager: ObservableObject {
    enum Tab: String { // ✅ Move Tab enum inside TabManager
        case dashboard
        case trends
        case foods
        case logs
        case cabinet
        case protocols
        case more
    }

    @Published var selectedTab: Tab = .dashboard
}
