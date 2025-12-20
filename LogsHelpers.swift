import SwiftUI

func colorForSeverity(_ s: Int) -> Color {
    switch s {
    case 1: return .green
    case 2: return .yellow
    case 3: return .orange
    case 4: return .red
    case 5: return .purple
    default: return .gray
    }
}

// ... other helper functions ...
