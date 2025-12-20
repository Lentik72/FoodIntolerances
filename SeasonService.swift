import Foundation

func getCurrentSeason(for date: Date) -> String {
    let calendar = Calendar.current
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)

    switch month {
    case 3:
        return day >= 20 ? "Spring" : "Winter"
    case 4, 5:
        return "Spring"
    case 6:
        return day >= 21 ? "Summer" : "Spring"
    case 7, 8:
        return "Summer"
    case 9:
        return day >= 23 ? "Fall" : "Summer"
    case 10, 11:
        return "Fall"
    case 12:
        return day >= 21 ? "Winter" : "Fall"
    default:
        return "Winter"
    }
}
