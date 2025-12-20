///
//  MoonPhaseService.swift
//  Food Intolerances
//
//  Created by Leo on [Date].
//

import Foundation
import SwiftAA

/// A service to calculate moon phases accurately using SwiftAA.
class MoonPhaseService {
    /// Returns the moon phase for a given date.
    /// - Parameter date: The date for which to calculate the moon phase.
    /// - Returns: A string representing the moon phase.
    func getMoonPhase(for date: Date) -> String {
        let astroDate = AstroDate(date: date)
        let moonPhase = astroDate.MoonPhase
        
        switch moonPhase {
        case 0:
            return "New Moon"
        case 0..<0.25:
            return "Waxing Crescent"
        case 0.25:
            return "First Quarter"
        case 0.25..<0.5:
            return "Waxing Gibbous"
        case 0.5:
            return "Full Moon"
        case 0.5..<0.75:
            return "Waning Gibbous"
        case 0.75:
            return "Last Quarter"
        case 0.75..<1.0:
            return "Waning Crescent"
        default:
            return "Unknown Phase"
        }
    }
    
    /// Returns the next moon phase after a given date.
    /// - Parameter date: The date after which to find the next moon phase.
    /// - Returns: A tuple containing the next moon phase and its date.
    func getNextMoonPhase(after date: Date) -> (phase: String, date: Date)? {
        let astroDate = AstroDate(date: date)
        if let nextPhase = astroDate.nextPhase(after: date) {
            let phaseName = getMoonPhase(for: nextPhase.Date)
            return (phaseName, nextPhase.Date)
        }
        return nil
    }
}
