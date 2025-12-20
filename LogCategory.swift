import Foundation

enum LogCategory: String, CaseIterable, Identifiable {
    case beverages = "Beverages"
    case meats = "Meats"
    case nutsAndSeeds = "Nuts & Seeds"
    case vegetables = "Vegetables"
    case supplements = "Supplements"
    case mental = "Mental"
    case environmental = "Environmental"
    case physical = "Physical"
    case other = "Other"
    
    var id: String { rawValue }
    
    var subcategories: [String] {
        switch self {
        case .beverages:
            return ["Water", "Coffee", "Tea", "Juice", "Alcohol", "Energy Drinks"]
        case .meats:
            return ["Beef", "Chicken", "Pork", "Fish", "Lamb"]
        case .nutsAndSeeds:
            return ["Almonds", "Walnuts", "Peanuts", "Sunflower Seeds", "Chia Seeds"]
        case .vegetables:
            return ["Leafy Greens", "Root Vegetables", "Cruciferous", "Nightshades"]
        case .supplements:
            return ["Vitamins", "Minerals", "Herbal", "Protein"]
        case .mental:
            return ["Stress", "Anxiety", "Depression", "Burnout"]
        case .environmental:
            return ["Weather", "Pollution", "Temperature", "Humidity"]
        case .physical:
            return ["Exercise", "Injury", "Fatigue", "Sleep"]
        case .other:
            return ["Unexplained", "Random", "Miscellaneous"]
        }
    }
}
