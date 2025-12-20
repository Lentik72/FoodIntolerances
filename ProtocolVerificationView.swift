// Create new file ProtocolVerificationView.swift
import SwiftUI
import SwiftData

struct ProtocolVerificationView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var `protocol`: TherapyProtocol
    @Environment(\.dismiss) private var dismiss
    
    @State private var safetyChecked = false
    @State private var effectivenessChecked = false
    @State private var contentVerified = false
    @State private var additionalNotes = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Protocol Verification")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(`protocol`.title)
                            .font(.headline)
                        
                        Text(`protocol`.category)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Verification Checklist")) {
                    Toggle("I've verified the instructions are safe to follow", isOn: $safetyChecked)
                    
                    Toggle("I've verified the effectiveness claims are reasonable", isOn: $effectivenessChecked)
                    
                    Toggle("I've verified content with reliable sources", isOn: $contentVerified)
                }
                
                Section(header: Text("Additional Notes")) {
                    TextEditor(text: $additionalNotes)
                        .frame(height: 100)
                }
                
                Section {
                    Button("Mark as Verified") {
                        markAsVerified()
                    }
                    .disabled(!safetyChecked || !effectivenessChecked || !contentVerified)
                }
                
                Section(header: Text("Current Status")) {
                    if let tags = `protocol`.tags {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                
                                if tag == "Web Source - Unverified" {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                }
                                
                                if tag == "Verified by User" {
                                    Spacer()
                                    Image(systemName: "checkmark.seal")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Verify Protocol")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
    
    private func markAsVerified() {
        // Remove unverified tags
        if var tags = `protocol`.tags {
            tags.removeAll { $0 == "Web Source - Unverified" || $0 == "Requires Verification" }
            tags.append("Verified by User")
            `protocol`.tags = tags
        } else {
            `protocol`.tags = ["Verified by User"]
        }
        
        // Add verification note
        let verificationNote = """
        VERIFICATION: This protocol has been verified by the user.
        
        Verification Notes:
        \(additionalNotes)
        
        Verified on: \(Date().formatted(date: .abbreviated, time: .shortened))
        """
        
        if var notes = `protocol`.notes {
            // Replace any disclaimer with verification note
            if notes.contains("DISCLAIMER") {
                notes = notes.replacingOccurrences(
                    of: "DISCLAIMER: This protocol was imported from the web and has not been medically verified.",
                    with: verificationNote
                )
            } else {
                notes += "\n\n" + verificationNote
            }
            
            `protocol`.notes = notes
        } else {
            `protocol`.notes = verificationNote
        }
        
        // Save changes
        try? modelContext.save()
        dismiss()
    }
}
