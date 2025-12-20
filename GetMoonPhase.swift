import Foundation

func getMoonPhase(for date: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let year = calendar.component(.year, from: date)
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)
    
    let yy = Double(year - (12 - month) / 10)
    var mm = Double(month + 9)
    if mm >= 12 {
        mm -= 12
    }
    mm += 1

    let k1 = floor(365.25 * (yy + 4712))
    let k2 = floor(30.6 * mm + 0.5)
    let k3 = floor(floor((yy / 100) + 49) * 0.75) - 38

    let julianDate = k1 + k2 + Double(day) + 59
    let jd = julianDate - k3

    let moonAge = (jd - 2451550.1) / 29.53058867
    let moonPhase = (moonAge - floor(moonAge)) * 29.53

    // 🌙 Determine Moon Phase Based on Moon Age
    switch moonPhase {
    case 0...1:
        return "New Moon 🌑"
    case 1...6.38264692644:
        return "Waxing Crescent 🌒"
    case 6.38264692644...8.38264692644:
        return "First Quarter 🌓"
    case 8.38264692644...13.76529385288:
        return "Waxing Gibbous 🌔"
    case 13.76529385288...15.76529385288:
        return "Full Moon 🌕"
    case 15.76529385288...21.14794077932:
        return "Waning Gibbous 🌖"
    case 21.14794077932...23.14794077932:
        return "Last Quarter 🌗"
    default:
        return "Waning Crescent 🌘"
    }
}
    
