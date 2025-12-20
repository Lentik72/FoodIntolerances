//
//  ViewExtensions.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 2/4/25.
//

import SwiftUI

extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith placeholder: Value) {
        self.init(
            get: { source.wrappedValue ?? placeholder },
            set: { newValue in
                source.wrappedValue = newValue
            }
        )
    }
}
