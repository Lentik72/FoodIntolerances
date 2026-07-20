# Temperature Units + Display Rounding — Design

**Date:** 2026-07-20
**Status:** Approved (decisions made interactively with Leo)
**Scope:** A **display-only** fix for the weather events shipped last round. Round temperature/humidity to whole numbers in the Timeline (today they render "19.6372 °C" / "69.3915 %"), and add a **°F/°C unit setting** that defaults to °F in the US (locale-based). The stored data and the evidence engine are untouched — °C stays the canonical unit.

**Not touched:** the weather ingestion/exposures/tiering (correct as shipped), `EventDisplay` (pure core — stays pref-unaware), any other units (weight, etc. — YAGNI).

---

## 1. Problem

The weather round emits `temperature` (°C) and `humidity` (%) `.environment` events. The Timeline renders their value line via `EventDisplay.valueLine`, whose generic `%g` fallthrough produces "19.6372 °C" / "69.3915 %" — too many digits. And °C is unfamiliar to US users, who expect °F. We need whole-number rounding and a user-selectable unit (default °F in the US), **without** touching stored data (the engine mines percentiles over canonical °C; changing storage or rounding-at-storage would lose precision before any °C→°F conversion).

## 2. Decisions (Leo, 2026-07-20)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Unit setting | A user-selectable **°C / °F** for temperature. Humidity is always %. |
| 2 | Default | **Locale-based** — US → °F, elsewhere → °C — resolved when the setting is unset; an explicit user choice overrides. |
| 3 | Rounding | Whole numbers, **rounded after any °C→°F conversion** (never before). |
| 4 | Layer | **Display-only** — canonical stored unit stays °C; `EventDisplay` (core) is untouched; the formatting lives in the app. |
| 5 | UI | A segmented **°C / °F** picker as a row in the **Health tab** settings list; changes reflect live in the Timeline. |
| 6 | Format | `20°C` / `68°F` / `69%` (unit/degree attached, no stray space). |

## 3. Architecture

### A. The unit + its resolution (app)

A small value type + a locale-aware resolver:

```swift
enum TemperatureUnit: String, CaseIterable { case celsius = "C", fahrenheit = "F"

    /// The device-locale default: US (imperial) → °F, everywhere else → °C.
    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
    /// Resolve the stored `@AppStorage` raw value: an explicit choice wins,
    /// an empty/unknown string falls back to the locale default.
    static func resolved(from raw: String) -> TemperatureUnit {
        TemperatureUnit(rawValue: raw) ?? localeDefault
    }
}
```

- Stored in `@AppStorage("hg.temperatureUnit")` as the raw string (default `""` → resolves to locale). Both the Timeline views and the settings picker bind to this one key, so changes propagate live.

### B. The formatter (app, pure + testable)

```swift
enum WeatherValueFormatter {
    /// The value line for a weather event, in the user's unit, rounded to a whole
    /// number. Returns nil for non-weather events (caller falls back to EventDisplay).
    static func line(for event: HealthEvent, unit: TemperatureUnit) -> String? {
        guard event.category == .environment, let v = event.value else { return nil }
        switch event.subtype {
        case "temperature":
            let shown = unit == .fahrenheit ? v * 9 / 5 + 32 : v      // stored °C
            return "\(Int(shown.rounded()))°\(unit == .fahrenheit ? "F" : "C")"
        case "humidity":
            return "\(Int(v.rounded()))%"
        default:
            return nil
        }
    }
}
```

### C. Wiring (app views)

`TimelineEventRow` (the visible value line ~`:40` **and** the accessibility string ~`:63`) and `EventDetailView` (~`:70`) each read `@AppStorage("hg.temperatureUnit")`, resolve the unit, and render:

```swift
let line = WeatherValueFormatter.line(for: event, unit: unit) ?? EventDisplay.valueLine(for: event)
```

So weather events get the new formatting; everything else is unchanged (`EventDisplay.valueLine` still handles symptoms/food/pressure/etc.). `EventDisplay` (core) is not modified.

### D. Setting UI (app)

A row in `HealthTabView`'s settings list (alongside "Safety reminders") — a labeled **segmented `Picker`** bound to `@AppStorage("hg.temperatureUnit")` over `TemperatureUnit.allCases` (shown as "°C" / "°F"). Because the stored value starts `""` (→ locale default), the picker should reflect the *resolved* unit on first show (seed the binding to `TemperatureUnit.resolved(from:).rawValue` if empty, so the segment isn't blank).

## 4. Reused / unchanged

- **`EventDisplay` (core)** — untouched; still the fallback for all non-weather value lines and unaffected by the pref.
- **The engine + storage** — °C stays canonical; percentile bucketing is over stored °C; no data migration.
- **Pressure** — already shows "hPa" via `EventDisplay`; not part of this round (no unit choice for pressure).

## 5. Testing

- **App (`-parallel-testing-enabled NO`):**
  - `WeatherValueFormatterTests` — a `temperature` event value `20` → `"20°C"` (celsius) and `"68°F"` (fahrenheit); a fractional °C (e.g. `19.6372`) → `"20°C"` / `"67°F"` (rounded *after* convert: 19.6372·9/5+32 = 67.35 → 67); a `humidity` event `69.39` → `"69%"`; a non-weather event (e.g. a symptom) → `nil` (so the fallback kicks in); a negative °C (e.g. `0` → `"32°F"`, `-5` → `"23°F"`) to confirm the conversion + no `>0`-style bug.
  - `TemperatureUnit.resolved(from:)` — `"F"` → fahrenheit, `"C"` → celsius, `""`/garbage → `localeDefault`.
- **Device:** the Timeline shows `20°C`/`68°F` and `69%` (no decimals); toggling the Health-tab picker flips the temperature unit live; humidity unaffected; light + dark.

## 6. Out of scope

- Weight / distance / other unit preferences (only temperature now).
- A unit choice for humidity or pressure.
- Any change to stored values, the engine, or `EventDisplay`.
- Re-emitting or migrating existing temperature events (they're already °C; display adapts).
