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

// MARK: - MoonPhase Enum Tests

struct MoonPhaseEnumTests {

    @Test func allPhasesHaveNames() async throws {
        for phase in MoonPhase.allCases {
            #expect(!phase.name.isEmpty, "MoonPhase \(phase) should have a name")
        }
    }

    @Test func allPhasesHaveEmojis() async throws {
        let moonEmojis = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
        for phase in MoonPhase.allCases {
            #expect(moonEmojis.contains(phase.emoji), "MoonPhase \(phase) should have a valid moon emoji")
        }
    }

    @Test func rawValueContainsNameAndEmoji() async throws {
        for phase in MoonPhase.allCases {
            #expect(phase.rawValue.contains(phase.name), "Raw value should contain the phase name")
            #expect(phase.rawValue.contains(phase.emoji), "Raw value should contain the emoji")
        }
    }

    @Test func matchesWorksWithVariousInputs() async throws {
        let fullMoon = MoonPhase.fullMoon
        #expect(fullMoon.matches("Full Moon"), "Should match exact name")
        #expect(fullMoon.matches("full moon"), "Should match lowercase")
        #expect(fullMoon.matches("FULL MOON"), "Should match uppercase")
        #expect(!fullMoon.matches("New Moon"), "Should not match different phase")
    }

    @Test func fromStringReturnsCorrectPhase() async throws {
        #expect(MoonPhase.from(string: "Full Moon") == .fullMoon)
        #expect(MoonPhase.from(string: "new moon") == .newMoon)
        #expect(MoonPhase.from(string: "waxing crescent") == .waxingCrescent)
        #expect(MoonPhase.from(string: "invalid") == nil)
    }
}

// MARK: - MercuryRetrograde Tests

struct MercuryRetrogradeTests {

    @Test func periodsAreNotEmpty() async throws {
        #expect(!MercuryRetrograde.periods.isEmpty, "Should have retrograde periods defined")
    }

    @Test func periodsHaveValidDateRanges() async throws {
        for period in MercuryRetrograde.periods {
            #expect(period.start < period.end, "Start date should be before end date")
        }
    }

    @Test func periodsAreChronologicallyOrdered() async throws {
        let periods = MercuryRetrograde.periods
        for i in 0..<(periods.count - 1) {
            #expect(periods[i].end < periods[i + 1].start, "Periods should not overlap")
        }
    }

    @Test func isRetrogradeReturnsTrueWithinPeriod() async throws {
        // Use the first defined period for testing
        if let firstPeriod = MercuryRetrograde.periods.first {
            let midPoint = Date(
                timeIntervalSince1970: (firstPeriod.start.timeIntervalSince1970 + firstPeriod.end.timeIntervalSince1970) / 2
            )
            #expect(MercuryRetrograde.isRetrograde(on: midPoint), "Should be retrograde within period")
        }
    }

    @Test func isRetrogradeReturnsFalseOutsidePeriods() async throws {
        // Create a date far in the past
        let calendar = Calendar.current
        if let pastDate = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1)) {
            #expect(!MercuryRetrograde.isRetrograde(on: pastDate), "Should not be retrograde in 2020")
        }
    }

    @Test func currentOrNextPeriodReturnsValue() async throws {
        // Should return a period for current date (either current or next)
        let result = MercuryRetrograde.currentOrNextPeriod(from: Date())
        // May be nil if all periods are in the past, but if we have future periods it should return one
        if !MercuryRetrograde.periods.isEmpty {
            let latestEnd = MercuryRetrograde.periods.map { $0.end }.max()!
            if Date() < latestEnd {
                #expect(result != nil, "Should return a period if there are future periods")
            }
        }
    }
}

// MARK: - PressureCategory Tests

struct PressureCategoryTests {

    @Test func lowPressureCategory() async throws {
        #expect(PressureCategory.from(pressure: 990) == .low)
        #expect(PressureCategory.from(pressure: 999) == .low)
        #expect(PressureCategory.from(pressure: 950) == .low)
    }

    @Test func normalPressureCategory() async throws {
        #expect(PressureCategory.from(pressure: 1000) == .normal)
        #expect(PressureCategory.from(pressure: 1010) == .normal)
        #expect(PressureCategory.from(pressure: 1020) == .normal)
    }

    @Test func highPressureCategory() async throws {
        #expect(PressureCategory.from(pressure: 1021) == .high)
        #expect(PressureCategory.from(pressure: 1030) == .high)
        #expect(PressureCategory.from(pressure: 1050) == .high)
    }

    @Test func allCategoriesHaveRawValues() async throws {
        for category in PressureCategory.allCases {
            #expect(!category.rawValue.isEmpty, "PressureCategory should have a raw value")
        }
    }
}

// MARK: - EnvironmentalThresholds Tests

struct EnvironmentalThresholdsTests {

    @Test func thresholdsHaveReasonableValues() async throws {
        #expect(EnvironmentalThresholds.suddenPressureChange > 0, "Pressure change threshold should be positive")
        #expect(EnvironmentalThresholds.defaultPressure > 900, "Default pressure should be reasonable")
        #expect(EnvironmentalThresholds.defaultPressure < 1100, "Default pressure should be reasonable")
        #expect(EnvironmentalThresholds.pressureReadingInterval > 0, "Reading interval should be positive")
        #expect(EnvironmentalThresholds.locationDistanceFilter > 0, "Distance filter should be positive")
        #expect(EnvironmentalThresholds.locationTimeout > 0, "Timeout should be positive")
    }

    @Test func defaultPressureIsStandardAtmosphere() async throws {
        // Standard atmospheric pressure is around 1013.25 hPa
        #expect(EnvironmentalThresholds.defaultPressure >= 1013, "Default should be near standard atmosphere")
        #expect(EnvironmentalThresholds.defaultPressure <= 1014, "Default should be near standard atmosphere")
    }
}

// MARK: - Logger Tests

struct LoggerTests {

    @Test func logLevelsHaveCorrectRawValues() async throws {
        #expect(Logger.Level.debug.rawValue.contains("DEBUG"))
        #expect(Logger.Level.info.rawValue.contains("INFO"))
        #expect(Logger.Level.warning.rawValue.contains("WARNING"))
        #expect(Logger.Level.error.rawValue.contains("ERROR"))
    }

    @Test func logCategoriesHaveNonEmptyRawValues() async throws {
        let categories: [Logger.Category] = [.app, .data, .ui, .network, .location, .health, .notification, .migration]
        for category in categories {
            #expect(!category.rawValue.isEmpty, "Category \(category) should have a non-empty raw value")
        }
    }

    @Test func allLogCategoriesAreDefined() async throws {
        // Verify all expected categories exist
        #expect(Logger.Category.app.rawValue == "App")
        #expect(Logger.Category.data.rawValue == "Data")
        #expect(Logger.Category.ui.rawValue == "UI")
        #expect(Logger.Category.network.rawValue == "Network")
        #expect(Logger.Category.location.rawValue == "Location")
        #expect(Logger.Category.health.rawValue == "Health")
        #expect(Logger.Category.notification.rawValue == "Notification")
        #expect(Logger.Category.migration.rawValue == "Migration")
    }

    @Test func logLevelsMapToOSLogTypes() async throws {
        // Verify OSLogType mapping exists (can't compare directly but can verify no crash)
        _ = Logger.Level.debug.osLogType
        _ = Logger.Level.info.osLogType
        _ = Logger.Level.warning.osLogType
        _ = Logger.Level.error.osLogType
    }

    @Test func loggerConfigurationMethodsExist() async throws {
        // Test that configuration methods can be called without crashing
        Logger.setEnabled(true)
        Logger.setMinimumLevel(.debug)
        // Restore default
        Logger.setEnabled(true)
    }

    @Test func loggerConvenienceMethodsExist() async throws {
        // Test that convenience methods can be called without crashing
        // These will log in DEBUG builds
        Logger.data("Test data message")
        Logger.network("Test network message")
        Logger.ui("Test UI message")
    }
}

// MARK: - AppConstants Tests

struct AppConstantsTests {

    @Test func severityRangeIsValid() async throws {
        #expect(AppConstants.Severity.min == 1)
        #expect(AppConstants.Severity.max == 5)
        #expect(AppConstants.Severity.range == 1...5)
    }

    @Test func severityDescriptionsExistForAllLevels() async throws {
        for level in AppConstants.Severity.range {
            let description = AppConstants.Severity.description(for: level)
            #expect(!description.isEmpty, "Severity level \(level) should have a description")
            #expect(description != "Unknown", "Severity level \(level) should have a known description")
        }
    }

    @Test func severityDescriptionReturnsUnknownForInvalidLevel() async throws {
        #expect(AppConstants.Severity.description(for: 0) == "Unknown")
        #expect(AppConstants.Severity.description(for: 6) == "Unknown")
        #expect(AppConstants.Severity.description(for: -1) == "Unknown")
    }

    @Test func atmosphericPressureCategoriesAreCorrect() async throws {
        #expect(AppConstants.AtmosphericPressure.categories.count == 3)
        #expect(AppConstants.AtmosphericPressure.low == "Low")
        #expect(AppConstants.AtmosphericPressure.normal == "Normal")
        #expect(AppConstants.AtmosphericPressure.high == "High")
    }

    @Test func statusValuesAreNonEmpty() async throws {
        #expect(!AppConstants.Status.active.isEmpty)
        #expect(!AppConstants.Status.inactive.isEmpty)
        #expect(!AppConstants.Status.loading.isEmpty)
        #expect(!AppConstants.Status.error.isEmpty)
    }

    @Test func limitsArePositive() async throws {
        #expect(AppConstants.Limits.maxTopResults > 0)
        #expect(AppConstants.Limits.maxRecentItems > 0)
        #expect(AppConstants.Limits.maxUpcomingReminders > 0)
        #expect(AppConstants.Limits.minCorrelationOccurrences > 0)
    }

    @Test func timeIntervalsArePositive() async throws {
        #expect(AppConstants.TimeInterval.minimumRefresh > 0)
        #expect(AppConstants.TimeInterval.pressureReadingInterval > 0)
        #expect(AppConstants.TimeInterval.confirmationDisplay > 0)
        #expect(AppConstants.TimeInterval.refreshDebounce > 0)
        #expect(AppConstants.TimeInterval.defaultGoalDuration > 0)
    }

    @Test func reminderIntervalsAreInOrder() async throws {
        #expect(AppConstants.TimeInterval.reminder1Hour < AppConstants.TimeInterval.reminder2Hours)
        #expect(AppConstants.TimeInterval.reminder2Hours < AppConstants.TimeInterval.reminder3Hours)
    }

    @Test func timeoutsArePositive() async throws {
        #expect(AppConstants.Timeout.atmosphericFetch > 0)
        #expect(AppConstants.Timeout.locationRequest > 0)
        #expect(AppConstants.Timeout.debounceDelay > 0)
        #expect(AppConstants.Timeout.locationRetry > 0)
    }
}

// MARK: - UIConstants Tests

struct UIConstantsTests {

    @Test func spacingValuesAreNonNegative() async throws {
        #expect(UIConstants.Spacing.none >= 0)
        #expect(UIConstants.Spacing.minimal >= 0)
        #expect(UIConstants.Spacing.extraSmall >= 0)
        #expect(UIConstants.Spacing.small >= 0)
        #expect(UIConstants.Spacing.base >= 0)
        #expect(UIConstants.Spacing.medium >= 0)
        #expect(UIConstants.Spacing.large >= 0)
        #expect(UIConstants.Spacing.extraLarge >= 0)
    }

    @Test func spacingValuesAreInOrder() async throws {
        #expect(UIConstants.Spacing.none < UIConstants.Spacing.minimal)
        #expect(UIConstants.Spacing.minimal < UIConstants.Spacing.extraSmall)
        #expect(UIConstants.Spacing.extraSmall < UIConstants.Spacing.small)
        #expect(UIConstants.Spacing.small < UIConstants.Spacing.base)
        #expect(UIConstants.Spacing.base < UIConstants.Spacing.medium)
        #expect(UIConstants.Spacing.medium < UIConstants.Spacing.large)
        #expect(UIConstants.Spacing.large < UIConstants.Spacing.extraLarge)
    }

    @Test func cornerRadiusValuesArePositive() async throws {
        #expect(UIConstants.CornerRadius.minimal > 0)
        #expect(UIConstants.CornerRadius.small > 0)
        #expect(UIConstants.CornerRadius.medium > 0)
        #expect(UIConstants.CornerRadius.large > 0)
        #expect(UIConstants.CornerRadius.extraLarge > 0)
    }

    @Test func opacityValuesAreInValidRange() async throws {
        let opacities = [
            UIConstants.Opacity.veryLight,
            UIConstants.Opacity.light,
            UIConstants.Opacity.minimal,
            UIConstants.Opacity.subtle,
            UIConstants.Opacity.medium,
            UIConstants.Opacity.mediumStrong,
            UIConstants.Opacity.strong
        ]
        for opacity in opacities {
            #expect(opacity >= 0.0 && opacity <= 1.0, "Opacity \(opacity) should be between 0 and 1")
        }
    }

    @Test func heightValuesArePositive() async throws {
        #expect(UIConstants.Height.imagePreview > 0)
        #expect(UIConstants.Height.chartSmall > 0)
        #expect(UIConstants.Height.chartMedium > 0)
        #expect(UIConstants.Height.chartLarge > 0)
        #expect(UIConstants.Height.bodyMapModal > 0)
        #expect(UIConstants.Height.standardButton > 0)
    }

    @Test func chartHeightsAreInOrder() async throws {
        #expect(UIConstants.Height.chartSmall < UIConstants.Height.chartMedium)
        #expect(UIConstants.Height.chartMedium < UIConstants.Height.chartLarge)
    }

    @Test func animationDurationsArePositive() async throws {
        #expect(UIConstants.Animation.quick > 0)
        #expect(UIConstants.Animation.mediumFast > 0)
        #expect(UIConstants.Animation.medium > 0)
    }

    @Test func scaleValuesAreReasonable() async throws {
        #expect(UIConstants.Scale.buttonPress < 1.0, "Button press scale should be less than 1")
        #expect(UIConstants.Scale.hover > 1.0, "Hover scale should be greater than 1")
        #expect(UIConstants.Scale.slightExpansion > 1.0, "Expansion should be greater than 1")
        #expect(UIConstants.Scale.emphasis > 1.0, "Emphasis scale should be greater than 1")
    }
}
