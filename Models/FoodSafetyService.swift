import Foundation
import SwiftData

/// Service for checking food safety against user's allergies and sensitivities
class FoodSafetyService {

    // MARK: - Cross-Reactivity Database

    /// Maps allergens to their cross-reactive foods
    /// Based on oral allergy syndrome (OAS) and protein similarity research
    static let crossReactivities: [String: [String]] = [
        // Pollen-Food Cross-Reactions (Oral Allergy Syndrome)
        "Birch Pollen": [
            "apples", "apple", "pears", "pear", "peaches", "peach", "plums", "plum",
            "cherries", "cherry", "apricots", "apricot", "nectarines", "nectarine",
            "carrots", "carrot", "celery", "parsley", "parsnip", "parsnips",
            "hazelnuts", "hazelnut", "almonds", "almond", "walnuts", "walnut",
            "kiwi", "kiwis", "kiwifruit"
        ],
        "Ragweed": [
            "melons", "melon", "watermelon", "cantaloupe", "honeydew",
            "bananas", "banana", "zucchini", "cucumbers", "cucumber",
            "sunflower seeds", "chamomile", "echinacea"
        ],
        "Grass Pollen": [
            "tomatoes", "tomato", "potatoes", "potato", "melons", "melon",
            "oranges", "orange", "wheat", "peaches", "peach"
        ],
        "Mugwort": [
            "celery", "carrots", "carrot", "parsley", "coriander", "fennel",
            "aniseed", "cumin", "peppers", "pepper", "sunflower seeds",
            "mangoes", "mango"
        ],

        // Latex-Fruit Syndrome
        "Latex": [
            "bananas", "banana", "avocados", "avocado", "kiwi", "kiwis",
            "chestnuts", "chestnut", "papaya", "papayas", "passion fruit",
            "figs", "fig", "strawberries", "strawberry", "potatoes", "potato",
            "tomatoes", "tomato"
        ],

        // Shellfish Cross-Reactivity
        "Shellfish": [
            "shrimp", "prawns", "prawn", "crab", "crabs", "lobster", "lobsters",
            "crayfish", "crawfish", "langoustine", "langoustines", "scallops",
            "scallop", "clams", "clam", "mussels", "mussel", "oysters", "oyster",
            "squid", "calamari", "octopus"
        ],

        // Tree Nut Cross-Reactivity
        "Tree Nuts": [
            "almonds", "almond", "cashews", "cashew", "walnuts", "walnut",
            "pecans", "pecan", "pistachios", "pistachio", "brazil nuts",
            "brazil nut", "macadamia", "macadamia nuts", "hazelnuts", "hazelnut",
            "chestnuts", "chestnut", "pine nuts", "pine nut"
        ],

        // Peanut (Legume family)
        "Peanuts": [
            "peanuts", "peanut", "peanut butter", "groundnuts",
            // Other legumes (less common cross-reaction)
            "soybeans", "soy", "lentils", "lentil", "chickpeas", "chickpea",
            "beans", "peas", "lupine", "lupin"
        ],

        // Milk/Dairy
        "Dairy": [
            "milk", "cheese", "butter", "cream", "yogurt", "yoghurt",
            "ice cream", "whey", "casein", "lactose", "ghee", "kefir",
            "sour cream", "cottage cheese", "cream cheese", "parmesan",
            "mozzarella", "cheddar", "brie", "camembert", "ricotta"
        ],

        // Egg
        "Eggs": [
            "eggs", "egg", "egg whites", "egg yolks", "mayonnaise", "mayo",
            "meringue", "albumin", "globulin", "lysozyme", "ovalbumin"
        ],

        // Wheat/Gluten
        "Gluten": [
            "wheat", "bread", "pasta", "noodles", "flour", "baked goods",
            "barley", "rye", "spelt", "semolina", "couscous", "bulgur",
            "farro", "kamut", "triticale", "seitan", "malt", "beer"
        ],

        // Soy
        "Soy": [
            "soy", "soybeans", "soybean", "soy sauce", "tofu", "tempeh",
            "edamame", "miso", "soy milk", "soy protein", "textured vegetable protein",
            "tvp", "soy lecithin"
        ],

        // Fish
        "Fish": [
            "fish", "salmon", "tuna", "cod", "tilapia", "halibut", "haddock",
            "trout", "bass", "mackerel", "sardines", "anchovies", "anchovy",
            "fish sauce", "fish oil", "omega-3", "caviar", "roe"
        ],

        // Sesame
        "Sesame": [
            "sesame", "sesame seeds", "tahini", "hummus", "sesame oil",
            "halvah", "halva"
        ],

        // Sulfites
        "Sulfites": [
            "wine", "dried fruits", "dried fruit", "grape juice", "pickles",
            "vinegar", "shrimp", "processed potatoes", "beer", "cider"
        ],

        // Histamine (for histamine intolerance)
        "Histamine": [
            "aged cheese", "fermented foods", "wine", "beer", "champagne",
            "sauerkraut", "kimchi", "yogurt", "kefir", "cured meats",
            "smoked fish", "shellfish", "spinach", "eggplant", "avocado",
            "tomatoes", "tomato", "strawberries", "citrus", "chocolate",
            "vinegar", "soy sauce"
        ],

        // FODMAP (for IBS/FODMAP sensitivity)
        "FODMAPs": [
            "garlic", "onions", "onion", "wheat", "rye", "lactose", "milk",
            "apples", "apple", "pears", "pear", "watermelon", "mango",
            "honey", "high fructose corn syrup", "agave", "beans", "lentils",
            "chickpeas", "artichokes", "asparagus", "cauliflower", "mushrooms"
        ]
    ]

    /// Common food aliases to help with matching
    static let foodAliases: [String: [String]] = [
        "prawns": ["shrimp"],
        "calamari": ["squid"],
        "cheddar": ["cheese"],
        "parmesan": ["cheese"],
        "mozzarella": ["cheese"],
        "brie": ["cheese"],
        "yoghurt": ["yogurt"],
        "groundnuts": ["peanuts"],
        "courgette": ["zucchini"],
        "aubergine": ["eggplant"],
        "capsicum": ["pepper", "bell pepper"],
        "coriander": ["cilantro"],
        "rocket": ["arugula"],
        "chips": ["fries", "potato"],
        "crisps": ["chips", "potato"]
    ]

    // MARK: - Food Safety Check

    /// Check if a food is safe for the user based on their allergies
    /// - Parameters:
    ///   - foodName: The food to check
    ///   - userAllergies: User's list of allergies
    ///   - learnedTriggers: Optional learned triggers from AIMemory
    /// - Returns: FoodSafetyResult with status and explanation
    func checkFood(
        _ foodName: String,
        userAllergies: [UserAllergy],
        learnedTriggers: [AIMemory] = []
    ) -> FoodSafetyResult {
        let normalizedFood = foodName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check direct allergy match
        if let directMatch = checkDirectAllergyMatch(normalizedFood, allergies: userAllergies) {
            return directMatch
        }

        // 2. Check cross-reactivity
        if let crossReaction = checkCrossReactivity(normalizedFood, allergies: userAllergies) {
            return crossReaction
        }

        // 3. Check learned triggers
        if let learnedTrigger = checkLearnedTriggers(normalizedFood, triggers: learnedTriggers) {
            return learnedTrigger
        }

        // 4. Check if food might contain common allergens
        if let containsWarning = checkCommonAllergenContent(normalizedFood, allergies: userAllergies) {
            return containsWarning
        }

        // Food appears safe
        return FoodSafetyResult(
            status: .safe,
            foodName: foodName,
            explanation: "No known allergies or sensitivities to \(foodName) in your profile.",
            relatedAllergy: nil,
            crossReactionSource: nil,
            additionalNotes: getGeneralNotes(for: normalizedFood)
        )
    }

    // MARK: - Private Check Methods

    private func checkDirectAllergyMatch(_ food: String, allergies: [UserAllergy]) -> FoodSafetyResult? {
        for allergy in allergies {
            let allergyName = allergy.name.lowercased()
            let crossReactiveItems = allergy.crossReactiveItems.map { $0.lowercased() }

            // Direct name match
            if food.contains(allergyName) || allergyName.contains(food) {
                return FoodSafetyResult(
                    status: .avoid,
                    foodName: food,
                    explanation: "You have a \(allergy.severityEnum.rawValue.lowercased()) \(allergy.allergyTypeEnum.rawValue.lowercased()) to \(allergy.name).",
                    relatedAllergy: allergy,
                    crossReactionSource: nil,
                    additionalNotes: buildAllergyNotes(allergy)
                )
            }

            // Check cross-reactive items stored with the allergy
            for item in crossReactiveItems {
                if food.contains(item) || item.contains(food) {
                    return FoodSafetyResult(
                        status: .avoid,
                        foodName: food,
                        explanation: "\(food.capitalized) is in your \(allergy.name) cross-reactive foods list.",
                        relatedAllergy: allergy,
                        crossReactionSource: allergy.name,
                        additionalNotes: buildAllergyNotes(allergy)
                    )
                }
            }
        }
        return nil
    }

    private func checkCrossReactivity(_ food: String, allergies: [UserAllergy]) -> FoodSafetyResult? {
        for allergy in allergies {
            let allergyName = allergy.name

            // Find matching cross-reactivity category
            for (category, foods) in Self.crossReactivities {
                let categoryLower = category.lowercased()
                let allergyLower = allergyName.lowercased()

                // Check if this allergy matches a category
                if categoryLower.contains(allergyLower) || allergyLower.contains(categoryLower) ||
                   isAllergyInCategory(allergyName: allergyLower, category: categoryLower) {

                    // Check if food is in cross-reactive list
                    if foods.contains(where: { food.contains($0) || $0.contains(food) }) {
                        let severity: SafetyStatus = allergy.severityEnum == .severe ? .avoid : .caution

                        return FoodSafetyResult(
                            status: severity,
                            foodName: food,
                            explanation: "You're allergic to \(allergyName). \(food.capitalized) can cause oral allergy syndrome (OAS) in people with \(allergyName.lowercased()) allergies.",
                            relatedAllergy: allergy,
                            crossReactionSource: category,
                            additionalNotes: [
                                "Symptoms may include: Itchy mouth, throat tingling, mild swelling",
                                "Cooking \(food) usually reduces or eliminates this risk",
                                "Reaction is typically mild but monitor for worsening symptoms"
                            ]
                        )
                    }
                }
            }
        }
        return nil
    }

    private func isAllergyInCategory(allergyName: String, category: String) -> Bool {
        // Map common allergy names to categories
        let allergyToCategory: [String: [String]] = [
            "dairy": ["lactose", "milk", "casein", "whey"],
            "gluten": ["wheat", "celiac", "coeliac"],
            "tree nuts": ["almonds", "cashews", "walnuts", "pecans", "pistachios", "hazelnuts", "macadamia"],
            "shellfish": ["shrimp", "crab", "lobster", "prawn"],
            "peanuts": ["peanut", "groundnut"],
            "eggs": ["egg"],
            "fish": ["salmon", "tuna", "cod"],
            "soy": ["soya", "soybean"],
            "sesame": ["tahini"]
        ]

        for (cat, aliases) in allergyToCategory {
            if category.contains(cat) {
                if aliases.contains(where: { allergyName.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private func checkLearnedTriggers(_ food: String, triggers: [AIMemory]) -> FoodSafetyResult? {
        let foodTriggers = triggers.filter { memory in
            guard memory.memoryTypeEnum == .trigger,
                  let trigger = memory.trigger?.lowercased() else { return false }
            return food.contains(trigger) || trigger.contains(food)
        }

        if let bestMatch = foodTriggers.sorted(by: { $0.confidence > $1.confidence }).first {
            let confidenceText = bestMatch.confidence >= 0.7 ? "often" : "sometimes"

            return FoodSafetyResult(
                status: .caution,
                foodName: food,
                explanation: "\(food.capitalized) \(confidenceText) triggers \(bestMatch.symptom ?? "symptoms") for you based on your history.",
                relatedAllergy: nil,
                crossReactionSource: nil,
                additionalNotes: [
                    "This is based on \(bestMatch.occurrenceCount) logged occurrence(s)",
                    "Confidence: \(Int(bestMatch.confidence * 100))%",
                    bestMatch.userConfirmed ? "You confirmed this trigger" : "Consider confirming or dismissing this pattern"
                ]
            )
        }
        return nil
    }

    private func checkCommonAllergenContent(_ food: String, allergies: [UserAllergy]) -> FoodSafetyResult? {
        // Foods that commonly contain allergens
        let foodsContainingAllergens: [String: [String]] = [
            "caesar salad": ["dairy", "eggs", "fish"],
            "pad thai": ["peanuts", "fish", "eggs", "shellfish"],
            "fried rice": ["eggs", "soy", "shellfish"],
            "pizza": ["dairy", "gluten"],
            "pasta": ["gluten", "eggs"],
            "bread": ["gluten", "eggs", "dairy"],
            "cake": ["gluten", "eggs", "dairy"],
            "cookies": ["gluten", "eggs", "dairy", "tree nuts"],
            "ice cream": ["dairy", "eggs"],
            "chocolate": ["dairy", "soy"],
            "sushi": ["fish", "shellfish", "soy", "sesame"],
            "hummus": ["sesame"],
            "pesto": ["tree nuts", "dairy"],
            "curry": ["dairy", "tree nuts", "shellfish"],
            "stir fry": ["soy", "shellfish", "peanuts"],
            "granola": ["tree nuts", "gluten", "dairy"],
            "protein bar": ["dairy", "soy", "tree nuts", "peanuts"]
        ]

        for (foodItem, containedAllergens) in foodsContainingAllergens {
            if food.contains(foodItem) {
                let relevantAllergies = allergies.filter { allergy in
                    containedAllergens.contains(where: { allergen in
                        allergy.name.lowercased().contains(allergen) ||
                        allergen.contains(allergy.name.lowercased())
                    })
                }

                if let firstMatch = relevantAllergies.first {
                    return FoodSafetyResult(
                        status: .caution,
                        foodName: food,
                        explanation: "\(food.capitalized) typically contains ingredients related to your \(firstMatch.name) sensitivity.",
                        relatedAllergy: firstMatch,
                        crossReactionSource: nil,
                        additionalNotes: [
                            "Check ingredients before consuming",
                            "Ask about preparation if eating out"
                        ]
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Helper Methods

    private func buildAllergyNotes(_ allergy: UserAllergy) -> [String] {
        var notes: [String] = []

        if allergy.severityEnum == .severe {
            notes.append("This is a SEVERE allergy - avoid completely")
        }

        if !allergy.knownReactions.isEmpty {
            notes.append("Known reactions: \(allergy.knownReactions.joined(separator: ", "))")
        }

        if !allergy.helpfulMedications.isEmpty {
            notes.append("Keep \(allergy.helpfulMedications.joined(separator: ", ")) available")
        }

        if let dateAdded = allergy.dateDiscovered {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            notes.append("Discovered: \(formatter.string(from: dateAdded))")
        }

        return notes
    }

    private func getGeneralNotes(for food: String) -> [String] {
        // Provide general health notes for common foods
        var notes: [String] = []

        // High histamine foods
        let highHistamine = ["aged cheese", "wine", "beer", "fermented", "cured meat", "smoked fish", "avocado", "spinach", "eggplant", "tomato", "strawberry", "citrus", "chocolate"]
        if highHistamine.contains(where: { food.contains($0) }) {
            notes.append("Note: This food is high in histamine - if you have histamine sensitivity, start with small amounts")
        }

        // High FODMAP foods
        let highFodmap = ["garlic", "onion", "wheat", "apple", "pear", "watermelon", "mango", "honey", "beans", "lentils", "mushroom"]
        if highFodmap.contains(where: { food.contains($0) }) {
            notes.append("Note: This food is high in FODMAPs - may cause digestive issues in sensitive individuals")
        }

        return notes
    }

    // MARK: - Batch Checking

    /// Check multiple foods at once
    func checkFoods(
        _ foods: [String],
        userAllergies: [UserAllergy],
        learnedTriggers: [AIMemory] = []
    ) -> [FoodSafetyResult] {
        return foods.map { checkFood($0, userAllergies: userAllergies, learnedTriggers: learnedTriggers) }
    }

    /// Get all unsafe foods from a list
    func filterUnsafeFoods(
        _ foods: [String],
        userAllergies: [UserAllergy],
        learnedTriggers: [AIMemory] = []
    ) -> [FoodSafetyResult] {
        return checkFoods(foods, userAllergies: userAllergies, learnedTriggers: learnedTriggers)
            .filter { $0.status != .safe }
    }
}

// MARK: - Food Safety Result

/// Result of a food safety check
struct FoodSafetyResult: Identifiable {
    let id = UUID()
    let status: SafetyStatus
    let foodName: String
    let explanation: String
    let relatedAllergy: UserAllergy?
    let crossReactionSource: String?
    let additionalNotes: [String]

    var statusIcon: String {
        switch status {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .avoid: return "xmark.circle.fill"
        }
    }

    var statusColor: String {
        switch status {
        case .safe: return "green"
        case .caution: return "orange"
        case .avoid: return "red"
        }
    }
}

/// Safety status for a food
enum SafetyStatus: String, CaseIterable {
    case safe = "Safe"
    case caution = "Caution"
    case avoid = "Avoid"

    var description: String {
        switch self {
        case .safe: return "No known issues"
        case .caution: return "Possible cross-reaction or past trigger"
        case .avoid: return "Direct allergy match"
        }
    }
}
