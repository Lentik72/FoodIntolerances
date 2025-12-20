// Create a new file: ProtocolSharingService.swift
import Foundation
import SwiftUI
import UniformTypeIdentifiers

class ProtocolSharingService {
    // Export a protocol to a file
    func exportProtocolToFile(_ protocol: TherapyProtocol) -> URL? {
        // Convert protocol to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        guard let jsonData = try? encoder.encode(ProtocolExportData(from: `protocol`)) else {
            print("Failed to encode protocol to JSON")
            return nil
        }
        
        // Create temporary file
        let fileName = `protocol`.title.replacingOccurrences(of: " ", with: "_") + ".protocol"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to write protocol to file: \(error)")
            return nil
        }
    }
    
    // Import a protocol from a file
    func importProtocolFromFile(_ fileURL: URL) -> TherapyProtocol? {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let exportData = try decoder.decode(ProtocolExportData.self, from: data)
            return exportData.toTherapyProtocol()
        } catch {
            print("Failed to import protocol: \(error)")
            return nil
        }
    }
    
    // Export a protocol as a formatted text (for sharing via message, email, etc.)
    func exportProtocolAsText(_ protocol: TherapyProtocol) -> String {
        var text = """
        PROTOCOL: \(`protocol`.title)
        CATEGORY: \(`protocol`.category)
        
        INSTRUCTIONS:
        \(`protocol`.instructions)
        
        FREQUENCY: \(`protocol`.frequency)
        DURATION: \(`protocol`.duration)
        
        """
        
        if let symptoms = `protocol`.symptoms, !symptoms.isEmpty {
            text += "SYMPTOMS: \(symptoms.joined(separator: ", "))\n\n"
        }
        
        if let notes = `protocol`.notes, !notes.isEmpty {
            text += "NOTES: \(notes)\n\n"
        }
        
        text += "Shared from Symptom Tracker App"
        
        return text
    }
}

// Structured data for export/import
struct ProtocolExportData: Codable {
    let title: String
    let category: String
    let instructions: String
    let frequency: String
    let timeOfDay: String
    let duration: String
    let symptoms: [String]?
    let notes: String?
    let tags: [String]?
    
    init(from protocol: TherapyProtocol) {
        self.title = `protocol`.title
        self.category = `protocol`.category
        self.instructions = `protocol`.instructions
        self.frequency = `protocol`.frequency
        self.timeOfDay = `protocol`.timeOfDay
        self.duration = `protocol`.duration
        self.symptoms = `protocol`.symptoms
        self.notes = `protocol`.notes
        self.tags = `protocol`.tags
    }
    
    func toTherapyProtocol() -> TherapyProtocol {
        return TherapyProtocol(
            title: title,
            category: category,
            instructions: instructions,
            frequency: frequency,
            timeOfDay: timeOfDay,
            duration: duration,
            symptoms: symptoms ?? [],
            startDate: Date(),
            notes: notes,
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: tags
        )
    }
}

// Create a UTType for protocol files
extension UTType {
    static var therapyProtocol: UTType {
        UTType(exportedAs: "com.yourdomain.symptomtracker.protocol")
    }
}
