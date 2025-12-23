import SwiftUI
import SwiftData
import Combine

class ProtocolFetchService: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var fetchedProtocols: [ProtocolExtraction] = []
    
    // For tracking and limiting API requests
    private var lastFetchTime: Date = .distantPast
    private let fetchCooldown: TimeInterval = 10 // 10 seconds between fetches
    
    func searchProtocols(query: String) async {
        // Debounce rapid searches
        let now = Date()
        if now.timeIntervalSince(lastFetchTime) < fetchCooldown && !fetchedProtocols.isEmpty {
            Logger.debug("Search cooldown active - using cached results", category: .network)
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // This would be replaced with actual API call
        // For now, create some sample protocols based on the query
        do {
            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_500_000_000)
            
            // Create sample protocols based on search query
            let sampleProtocols = createSampleProtocols(for: query)
            
            await MainActor.run {
                self.fetchedProtocols = sampleProtocols
                self.isLoading = false
                self.lastFetchTime = Date()
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // Temporary function to create sample protocols for demo
    private func createSampleProtocols(for query: String) -> [ProtocolExtraction] {
        let lowercaseQuery = query.lowercased()
        var protocols: [ProtocolExtraction] = []
        
        // Create samples based on common symptoms
        if lowercaseQuery.contains("headache") || lowercaseQuery.contains("migraine") {
            protocols.append(
                ProtocolExtraction(
                    title: "Natural Headache Relief Protocol",
                    instructions: "1. Apply lavender or peppermint essential oil to temples\n2. Stay hydrated with at least 8oz of water\n3. Rest in a dark, quiet room for 30 minutes\n4. Try gentle neck stretches",
                    dosage: "Apply as needed up to 3 times daily",
                    duration: "Continue until symptoms subside, typically 1-3 days",
                    sourceURL: "https://example.com/headache-protocol",
                    category: "Pain Management",
                    symptoms: ["Headache", "Migraine", "Tension"]
                )
            )
            
            protocols.append(
                ProtocolExtraction(
                    title: "Magnesium Protocol for Chronic Migraines",
                    instructions: "1. Take magnesium glycinate supplement with food\n2. Increase intake of magnesium-rich foods like dark leafy greens, nuts, and seeds\n3. Consider epsom salt baths in the evening",
                    dosage: "300-400mg magnesium daily, divided into morning and evening doses",
                    duration: "4-6 weeks minimum to evaluate effectiveness",
                    sourceURL: "https://example.com/magnesium-migraine",
                    category: "Nutritional Support",
                    symptoms: ["Migraine", "Headache", "Sensitivity to Light"]
                )
            )
        }
        
        if lowercaseQuery.contains("sleep") || lowercaseQuery.contains("insomnia") {
            protocols.append(
                ProtocolExtraction(
                    title: "Natural Sleep Improvement Protocol",
                    instructions: "1. Take magnesium glycinate 1 hour before bed\n2. Drink chamomile tea 30 minutes before sleep\n3. Avoid screens 1 hour before bedtime\n4. Keep bedroom cool and dark",
                    dosage: "200-300mg magnesium, 1 cup of tea",
                    duration: "Follow nightly for at least 2 weeks",
                    sourceURL: "https://example.com/sleep-protocol",
                    category: "Sleep Improvement",
                    symptoms: ["Insomnia", "Poor Sleep Quality", "Difficulty Falling Asleep"]
                )
            )
        }
        
        if lowercaseQuery.contains("digest") || 
           lowercaseQuery.contains("stomach") || 
           lowercaseQuery.contains("gut") {
            protocols.append(
                ProtocolExtraction(
                    title: "Gut Health Restoration Protocol",
                    instructions: "1. Take a high-quality probiotic on empty stomach\n2. Consume 1-2 tbsp of fermented foods with meals\n3. Drink ginger tea between meals\n4. Include prebiotic fiber sources daily",
                    dosage: "Probiotic: 30-50 billion CFU daily\nGinger tea: 2-3 cups daily",
                    duration: "4-6 weeks minimum",
                    sourceURL: "https://example.com/gut-protocol",
                    category: "Digestive Health",
                    symptoms: ["Bloating", "Indigestion", "Irregular Digestion"]
                )
            )
        }
        
        // Generic protocol if no matches
        if protocols.isEmpty {
            protocols.append(
                ProtocolExtraction(
                    title: "\(query.capitalized) Support Protocol",
                    instructions: "1. Research has shown herbal remedies may help with symptoms\n2. Consider dietary adjustments based on specific triggers\n3. Ensure proper hydration and rest",
                    dosage: "Follow specific recommendations for selected remedies",
                    duration: "2-4 weeks initially to evaluate effectiveness",
                    sourceURL: "https://example.com/general-protocol",
                    category: "General Health",
                    symptoms: [query.capitalized]
                )
            )
        }
        
        return protocols
    }
}
