//
//  OrientationObserver.swift
//  Food Intolerances
//
//  Created by Leo on [Date].
//

import SwiftUI
import Combine

class OrientationObserver: ObservableObject {
    @Published var isLandscape: Bool = UIDevice.current.orientation.isLandscape
    
    private var cancellable: AnyCancellable?
    
    init() {
        // Initial orientation
        self.isLandscape = UIDevice.current.orientation.isLandscape
        
        // Subscribe to orientation changes
        cancellable = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .receive(on: RunLoop.main)
            .map { _ in UIDevice.current.orientation.isLandscape }
            .assign(to: \.isLandscape, on: self)
    }
    
    deinit {
        cancellable?.cancel()
    }
}
