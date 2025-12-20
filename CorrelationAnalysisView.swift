// Create a new file: CorrelationAnalysisView.swift
import SwiftUI
import SwiftData
import Charts

struct CorrelationAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var logs: [LogEntry]
    
    @State private var selectedSymptom: String = ""
    @State private var potentialTriggers: [(String, Double)] = []
    @State private var envFactorCorrelation: [(String, Double)] = []
    
    var symptoms: [String] {
        Array(Set(logs.flatMap { $0.symptoms })).sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Correlation Analysis")
                .font(.title)
                .padding()
            
            Picker("Select Symptom", selection: $selectedSymptom) {
                ForEach(symptoms, id: \.self) { symptom in
                    Text(symptom).tag(symptom)
                }
            }
            .onChange(of: selectedSymptom) { oldValue, newValue in
                analyzeCorrelations()
            }
            .padding()
            
            if !potentialTriggers.isEmpty {
                VStack(alignment: .leading) {
                    Text("Potential Triggers")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Chart {
                        ForEach(potentialTriggers.prefix(5), id: \.0) { item in
                            BarMark(
                                x: .value("Correlation", item.1),
                                y: .value("Item", item.0)
                            )
                            .foregroundStyle(Color.red.gradient)
                        }
                    }
                    .frame(height: 200)
                    .padding()
                }
            }
            
            if !envFactorCorrelation.isEmpty {
                VStack(alignment: .leading) {
                    Text("Environmental Factors")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Chart {
                        ForEach(envFactorCorrelation, id: \.0) { item in
                            BarMark(
                                x: .value("Correlation", item.1),
                                y: .value("Factor", item.0)
                            )
                            .foregroundStyle(Color.blue.gradient)
                        }
                    }
                    .frame(height: 200)
                    .padding()
                }
            }
            
            Spacer()
        }
        .onAppear {
            if !symptoms.isEmpty {
                selectedSymptom = symptoms.first ?? ""
                analyzeCorrelations()
            }
        }
    }
    
    private func analyzeCorrelations() {
        guard !selectedSymptom.isEmpty else { return }
        
        // Filter logs with the selected symptom
        _ = logs.filter { $0.symptoms.contains(selectedSymptom) }
        
        // Analyze food correlations
        var foodItems: [String: (total: Int, withSymptom: Int)] = [:]
        
        for log in logs {
            if let food = log.foodDrinkItem, !food.isEmpty {
                foodItems[food, default: (0, 0)].total += 1
                
                if log.symptoms.contains(selectedSymptom) {
                    foodItems[food, default: (0, 0)].withSymptom += 1
                }
            }
        }
        
        // Calculate correlation coefficient
        potentialTriggers = foodItems.compactMap { item, counts in
            guard counts.total >= 3 else { return nil }  // Require at least 3 occurrences
            let correlation = Double(counts.withSymptom) / Double(counts.total)
            return (item, correlation)
        }
        .sorted { $0.1 > $1.1 }
        
        // Environmental factors correlation
        var moonPhases: [String: (total: Int, withSymptom: Int)] = [:]
        var pressures: [String: (total: Int, withSymptom: Int)] = [:]
        
        for log in logs {
            if !log.moonPhase.isEmpty {
                moonPhases[log.moonPhase, default: (0, 0)].total += 1
                
                if log.symptoms.contains(selectedSymptom) {
                    moonPhases[log.moonPhase, default: (0, 0)].withSymptom += 1
                }
            }
            
            if !log.atmosphericPressure.isEmpty {
                pressures[log.atmosphericPressure, default: (0, 0)].total += 1
                
                if log.symptoms.contains(selectedSymptom) {
                    pressures[log.atmosphericPressure, default: (0, 0)].withSymptom += 1
                }
            }
        }
        
        // Calculate correlations
        let moonCorrelations = moonPhases.compactMap { phase, counts -> (String, Double)? in
            guard counts.total >= 3 else { return nil }
            let correlation = Double(counts.withSymptom) / Double(counts.total)
            return ("Moon: \(phase)", correlation)
        }
        
        let pressureCorrelations = pressures.compactMap { pressure, counts -> (String, Double)? in
            guard counts.total >= 3 else { return nil }
            let correlation = Double(counts.withSymptom) / Double(counts.total)
            return ("Pressure: \(pressure)", correlation)
        }
        
        envFactorCorrelation = (moonCorrelations + pressureCorrelations).sorted { $0.1 > $1.1 }
    }
}
