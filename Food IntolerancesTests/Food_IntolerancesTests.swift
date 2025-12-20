//
//  Food_IntolerancesTests.swift
//  Food IntolerancesTests
//
//  Created by Leo on 12/18/24.
//

import Testing
import Foundation
@testable import Food_Intolerances

// MARK: - SymptomCatalog Tests

struct SymptomCatalogTests {

    @Test func allSymptomsReturnsNonEmptyArray() async throws {
        let symptoms = SymptomCatalog.allSymptoms()
        #expect(!symptoms.isEmpty, "Symptom catalog should not be empty")
    }

    @Test func allSymptomsHaveUniqueNames() async throws {
        let symptoms = SymptomCatalog.allSymptoms()
        let names = symptoms.map { $0.name }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "All symptom names should be unique")
    }

    @Test func symptomToRegionMappingWorks() async throws {
        let mapping = SymptomCatalog.symptomToRegionMapping()
        #expect(!mapping.isEmpty, "Symptom to region mapping should not be empty")

        // Check a known symptom
        #expect(mapping["Headache"] == "head", "Headache should map to head region")
        #expect(mapping["Bloating"] == "abdomen", "Bloating should map to abdomen region")
    }

    @Test func symptomsForRegionReturnsCorrectSymptoms() async throws {
        let headSymptoms = SymptomCatalog.symptoms(for: "head")
        #expect(!headSymptoms.isEmpty, "Head region should have symptoms")

        // All returned symptoms should be for the head region
        for symptom in headSymptoms {
            #expect(symptom.regionId == "head", "All symptoms should be for head region")
        }
    }

    @Test func predefinedSymptomNamesMatchesAllSymptoms() async throws {
        let names = SymptomCatalog.predefinedSymptomNames
        let allSymptoms = SymptomCatalog.allSymptoms()
        #expect(names.count == allSymptoms.count, "Predefined names count should match all symptoms count")
    }
}

// MARK: - CategoryLists Tests

struct CategoryListsTests {

    @Test func mentalCategoriesNotEmpty() async throws {
        #expect(!CategoryLists.mental.isEmpty, "Mental categories should not be empty")
        #expect(CategoryLists.mental.contains("Stress"), "Mental categories should contain Stress")
    }

    @Test func environmentalCategoriesNotEmpty() async throws {
        #expect(!CategoryLists.environmental.isEmpty, "Environmental categories should not be empty")
        #expect(CategoryLists.environmental.contains("Weather Changes"), "Environmental categories should contain Weather Changes")
    }

    @Test func physicalCategoriesNotEmpty() async throws {
        #expect(!CategoryLists.physical.isEmpty, "Physical categories should not be empty")
        #expect(CategoryLists.physical.contains("Exercise"), "Physical categories should contain Exercise")
    }

    @Test func foodAndDrinkCategoriesNotEmpty() async throws {
        #expect(!CategoryLists.foodAndDrink.isEmpty, "Food & Drink categories should not be empty")
        #expect(CategoryLists.foodAndDrink.contains("Dairy"), "Food & Drink categories should contain Dairy")
    }

    @Test func categoriesForCauseTypeReturnsCorrectData() async throws {
        let mental = CategoryLists.categories(for: .mental)
        #expect(mental == CategoryLists.mental, "categories(for: .mental) should return mental categories")

        let physical = CategoryLists.categories(for: .physical)
        #expect(physical == CategoryLists.physical, "categories(for: .physical) should return physical categories")
    }

    @Test func symptomTriggersNotEmpty() async throws {
        #expect(!CategoryLists.symptomTriggers.isEmpty, "Symptom triggers should not be empty")
        #expect(CategoryLists.symptomTriggers.contains("Weather Change"), "Symptom triggers should contain Weather Change")
    }
}

// MARK: - Moon Phase Tests

struct MoonPhaseTests {

    @Test func getMoonPhaseReturnsValidPhase() async throws {
        let phase = getMoonPhase(for: Date())
        #expect(!phase.isEmpty, "Moon phase should not be empty")

        // Check that the phase contains one of the expected values
        let validPhases = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                           "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        let containsValidPhase = validPhases.contains { phase.contains($0) }
        #expect(containsValidPhase, "Moon phase should be one of the known phases")
    }

    @Test func getMoonPhaseIncludesEmoji() async throws {
        let phase = getMoonPhase(for: Date())
        // Check for moon emoji
        let moonEmojis = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
        let containsEmoji = moonEmojis.contains { phase.contains($0) }
        #expect(containsEmoji, "Moon phase should include a moon emoji")
    }

    @Test func moonPhaseChangesOverTime() async throws {
        let today = Date()
        let twoWeeksLater = Calendar.current.date(byAdding: .day, value: 15, to: today)!

        let phaseToday = getMoonPhase(for: today)
        let phaseLater = getMoonPhase(for: twoWeeksLater)

        // Over 15 days, the moon phase should definitely be different
        #expect(phaseToday != phaseLater, "Moon phase should change over 15 days")
    }
}

// MARK: - CauseType Tests

struct CauseTypeTests {

    @Test func allCauseTypesHaveIds() async throws {
        for causeType in CauseType.allCases {
            #expect(!causeType.id.isEmpty, "CauseType \(causeType) should have a non-empty id")
        }
    }

    @Test func causeTypesAreCorrectlyNamed() async throws {
        #expect(CauseType.mental.rawValue == "Mental")
        #expect(CauseType.environmental.rawValue == "Environmental")
        #expect(CauseType.physical.rawValue == "Physical")
        #expect(CauseType.foodAndDrink.rawValue == "Food/Drink")
        #expect(CauseType.unknown.rawValue == "Unknown")
    }
}

// MARK: - LogStep Tests

struct LogStepTests {

    @Test func allLogStepsHaveTitles() async throws {
        for step in LogStep.allCases {
            #expect(!step.title.isEmpty, "LogStep \(step) should have a non-empty title")
        }
    }

    @Test func logStepsAreInCorrectOrder() async throws {
        #expect(LogStep.symptomSelection.rawValue == 0)
        #expect(LogStep.causeIdentification.rawValue == 1)
        #expect(LogStep.severityRating.rawValue == 2)
        #expect(LogStep.affectedAreas.rawValue == 3)
        #expect(LogStep.dateNotes.rawValue == 4)
        #expect(LogStep.review.rawValue == 5)
    }
}

// MARK: - LogCategory Tests

struct LogCategoryTests {

    @Test func allCategoriesHaveSubcategories() async throws {
        for category in LogCategory.allCases {
            #expect(!category.subcategories.isEmpty, "LogCategory \(category) should have subcategories")
        }
    }

    @Test func beveragesCategoryHasExpectedSubcategories() async throws {
        let subcategories = LogCategory.beverages.subcategories
        #expect(subcategories.contains("Water"))
        #expect(subcategories.contains("Coffee"))
        #expect(subcategories.contains("Tea"))
    }
}

// MARK: - SymptomDefinition Tests

struct SymptomDefinitionTests {

    @Test func symptomDefinitionEquality() async throws {
        let symptom1 = SymptomDefinition(name: "Headache", regionId: "head", category: .neurological)
        let symptom2 = SymptomDefinition(name: "Headache", regionId: "head", category: .neurological)
        let symptom3 = SymptomDefinition(name: "Migraine", regionId: "head", category: .neurological)

        // Same name means equal
        #expect(symptom1 == symptom2, "Symptoms with same name should be equal")
        #expect(symptom1 != symptom3, "Symptoms with different names should not be equal")
    }

    @Test func symptomDefinitionHashableByName() async throws {
        let symptom1 = SymptomDefinition(name: "Headache", regionId: "head", category: .neurological)
        let symptom2 = SymptomDefinition(name: "Headache", regionId: "neck", category: .physical)

        // Hash should be based on name only
        var set = Set<SymptomDefinition>()
        set.insert(symptom1)
        set.insert(symptom2)

        // Should only have 1 element since names are the same
        #expect(set.count == 1, "Set should dedupe by name")
    }
}
