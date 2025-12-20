import SwiftUI
import SwiftData
import Combine
import Charts

// MARK: - Color Extension (Random Colors for Charts)
extension Color {
    static func random() -> Color {
        return Color(
            red: Double.random(in: 0...1),
            green: Double.random(in: 0...1),
            blue: Double.random(in: 0...1)
        )
    }
}

    
    import UIKit
    
    extension UIApplication {
        func endEditing() {
            sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

