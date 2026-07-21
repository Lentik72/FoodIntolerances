import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct BodyMetricValueFormatterTests {
    /// A canonical body-weight event: category .bodyMetric, subtype "weight",
    /// unit "kg", value in kilograms (mirrors HealthKitSampleMapper's bodyMass row).
    private func weight(_ kg: Double?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                    subtype: "weight", value: kg, unit: "kg", source: .healthKit)
    }

    @Test func kilogramsRenderOneDecimal() {
        #expect(BodyMetricValueFormatter.line(for: weight(81.4), unit: .kilograms) == "81.4 kg")
        // A whole-number kg keeps its trailing ".0" — guards against an Int-style "90 kg"
        // regression (cf. UserProfile.weightDisplayString, which does render Int kg).
        #expect(BodyMetricValueFormatter.line(for: weight(90), unit: .kilograms) == "90.0 kg")
    }
    @Test func poundsConvertThenRenderOneDecimal() {
        // 81.4 × 2.20462 = 179.456… → "%.1f" → 179.5
        #expect(BodyMetricValueFormatter.line(for: weight(81.4), unit: .pounds) == "179.5 lb")
        // 90.0 × 2.20462 = 198.4158 → 198.4  (pins conversion + rounding direction)
        #expect(BodyMetricValueFormatter.line(for: weight(90), unit: .pounds) == "198.4 lb")
    }
    @Test func kilogramsRoundsToOneDecimal() {
        // The nearest double to 81.45 is >81.45 (NOT a half-tie), so "%.1f" rounds up to 81.5
        // under any rounding mode — deterministic, not platform-fragile. Discriminates round
        // vs truncate (truncation would give 81.4).
        #expect(BodyMetricValueFormatter.line(for: weight(81.45), unit: .kilograms) == "81.5 kg")
    }
    @Test func nonWeightEventReturnsNil() {   // caller falls back to WeatherValueFormatter / EventDisplay
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .symptom,
                                  subtype: "migraine", value: 5, source: .manual)
        #expect(BodyMetricValueFormatter.line(for: symptom, unit: .pounds) == nil)
        // bodyMetric but not the weight subtype → nil (defensive: only "weight" converts)
        let bodyFat = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                                  subtype: "bodyFat", value: 20, unit: "%", source: .healthKit)
        #expect(BodyMetricValueFormatter.line(for: bodyFat, unit: .pounds) == nil)
        // A future kg-unit bodyMetric that ISN'T weight (e.g. HealthKit lean body mass, also kg)
        // must still return nil — isolates the subtype guard from the unit guard.
        let leanMass = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                                   subtype: "leanBodyMass", value: 80, unit: "kg", source: .healthKit)
        #expect(BodyMetricValueFormatter.line(for: leanMass, unit: .pounds) == nil)
        // weight subtype but a non-kg unit → nil (guard pins the canonical-unit assumption)
        let oddUnit = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                                  subtype: "weight", value: 81.4, unit: "lb", source: .healthKit)
        #expect(BodyMetricValueFormatter.line(for: oddUnit, unit: .pounds) == nil)
        #expect(BodyMetricValueFormatter.line(for: weight(nil), unit: .kilograms) == nil)   // no value → nil
    }
    @Test func resolvedFromProfilePreference() {
        #expect(WeightUnit.resolved(preference: "imperial", locale: Locale(identifier: "de_DE")) == .pounds)   // explicit wins over locale
        #expect(WeightUnit.resolved(preference: "metric", locale: Locale(identifier: "en_US")) == .kilograms)  // explicit wins over locale
    }
    @Test func resolvedFallsBackToLocaleWhenNoOrUnknownPreference() {
        #expect(WeightUnit.resolved(preference: nil, locale: Locale(identifier: "en_US")) == .pounds)
        #expect(WeightUnit.resolved(preference: nil, locale: Locale(identifier: "en_GB")) == .kilograms)
        #expect(WeightUnit.resolved(preference: nil, locale: Locale(identifier: "de_DE")) == .kilograms)
        #expect(WeightUnit.resolved(preference: "garbage", locale: Locale(identifier: "en_US")) == .pounds)     // unknown → locale
        #expect(WeightUnit.resolved(preference: "garbage", locale: Locale(identifier: "de_DE")) == .kilograms)  // unknown → locale
    }
}
