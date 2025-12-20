//
//  TabEnum.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 1/30/25.
//

// TabEnum.swift

import Foundation

enum Tab: Int, CaseIterable, Identifiable {
    case dashboard = 0
    case trends
    case foods
    case protocols
    case ongoingSymptoms
    case logs

    var id: Int { self.rawValue }
}
