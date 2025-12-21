import SwiftUI

struct LogRowView: View {
    let log: LogEntry
    let fetchProtocol: (UUID) -> TherapyProtocol?
    let avoidedItems: [AvoidedItem]
    var onToggleStatus: ((LogEntry) -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LogHeaderView(log: log, severity: log.severity, onToggleStatus: onToggleStatus)
            
            if !log.subcategories.isEmpty {
                Text("Subcategory: \(log.subcategories.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // In LogRowView.swift, replace the existing warning code with this enhanced version
            if let foodDrink = log.foodDrinkItem, !foodDrink.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Food/Drink: \(foodDrink)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Enhanced warning display
                if avoidedItems.contains(where: { $0.name.lowercased() == foodDrink.lowercased() }) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.title3)
                        Text("This item is in your Avoid List!")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: 1)
                    )
                    .padding(.vertical, 4)
                }
            }
            
            EnvironmentalFactorsView(log: log)
            
            if let imageData = log.symptomPhotoData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 100)
            }
            
            if !log.notes.isEmpty {
                Text("Notes: \(log.notes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Severity: \(log.severity)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let protocolID = log.protocolID {
                ProtocolInfoView(
                    log: log,
                    therapyProtocol: fetchProtocol(protocolID)
                )
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct LogHeaderView: View {
    let log: LogEntry
    let severity: Int
    var onToggleStatus: ((LogEntry) -> Void)?
    
    var body: some View {
        HStack(alignment: .center) {
            Circle()
                .fill(BodyRegionUtility.colorForSeverity(severity))
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Symptom/s: \(log.itemName)")
                    .font(.headline)
                Text("Date: \(log.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Use nil-coalescing to provide a default value
            if log.isOngoing ?? false {
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(8)
                    .onTapGesture {
                        onToggleStatus?(log)
                    }
            } else {
                Text("Resolved")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray)
                    .cornerRadius(8)
                    .onTapGesture {
                        onToggleStatus?(log)
                    }
            }
        }
    }
}
    
private struct ProtocolInfoView: View {
    let log: LogEntry
    let therapyProtocol: TherapyProtocol?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Protocol Used:")
                .font(.caption)
                .foregroundColor(.blue)
            
            if let therapy = therapyProtocol {
                Text(therapy.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !log.symptoms.isEmpty {
                NavigationLink(destination: SymptomTrackingView(symptom: log.symptoms[0])) {
                    HStack {
                        Text("View Tracking")
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
            
            if let effectiveness = log.protocolEffectiveness {
                HStack {
                    Text("Effectiveness:")
                        .font(.caption)
                    StarRatingView(rating: effectiveness)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct StarRatingView: View {
    let rating: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundColor(.yellow)
                    .font(.caption2)
            }
        }
    }
}

struct LogRowView_Previews: PreviewProvider {
    static var previews: some View {
        LogRowView(
            log: LogEntry(),
            fetchProtocol: { _ in nil },
            avoidedItems: []
        )
    }
}
