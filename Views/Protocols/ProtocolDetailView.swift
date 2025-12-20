import SwiftUI
import SwiftData

struct ProtocolDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var therapyProtocol: TherapyProtocol
    var onSelect: ((TherapyProtocol) -> Void)? = nil

    @State private var showAddItemSheet = false
    @State private var showEditProtocolSheet = false
    @State private var showDuplicateSheet = false
    @State private var isExpanded = true
    @State private var showDeleteAlert = false
    @State private var duplicatedProtocol: TherapyProtocol?
    @State private var showVerifySheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // HEADER
                HStack {
                    Text(therapyProtocol.title)
                        .font(.largeTitle)
                        .bold()
                    Spacer()
                    if therapyProtocol.isWishlist {
                        Image(systemName: "star.circle.fill")
                            .foregroundColor(.yellow)
                            .font(.title2)
                    }
                }
                .padding(.horizontal)

                // Header with warning for unverified protocols
                if let tags = therapyProtocol.tags, tags.contains("Web Source - Unverified") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Unverified Web Source")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        
                        Text("This protocol was imported from the web and has not been medically verified. Review carefully and consult a healthcare professional before use.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            markAsVerified()
                        }) {
                            Text("Mark as Verified")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                // CATEGORY & SYMPTOMS
                HStack {
                    Text("Category: \(therapyProtocol.category)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Symptoms: \(therapyProtocol.symptoms?.joined(separator: ", ") ?? "No symptoms")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                
                // INSTRUCTIONS
                if !therapyProtocol.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Instructions:")
                            .font(.headline)
                        Text(therapyProtocol.instructions)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal)
                }

                // PROTOCOL ITEMS
                ProtocolItemsSection(
                    isExpanded: $isExpanded,
                    therapyProtocol: .constant(therapyProtocol),
                    deleteAction: deleteProtocolItem
                )

                // ACTION BUTTONS
                VStack(spacing: 10) {
                    if let onSelect = onSelect {
                        Button {
                            onSelect(therapyProtocol)
                        } label: {
                            Label("Select Protocol", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                        .padding(.horizontal)
                    }

                    if let notes = therapyProtocol.notes, notes.contains("Source: http") {
                        // Extract URL from notes
                        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                        let matches = detector.matches(in: notes, options: [], range: NSRange(location: 0, length: notes.utf16.count))
                        
                        if let match = matches.first, let url = match.url {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Label("View Original Source", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(.orange)
                            .padding(.horizontal)
                        }
                    }
                    
                    Button {
                        showAddItemSheet = true
                    } label: {
                        Label("Add Item", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .padding(.horizontal)
                    

                    Button {
                        showEditProtocolSheet = true
                    } label: {
                        Label("Edit Protocol", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.blue)
                    .padding(.horizontal)

                    if let tags = therapyProtocol.tags, tags.contains("Web Source - Unverified") {
                        Button {
                            showVerifySheet = true
                        } label: {
                            Label("Verify Protocol", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.orange)
                        .padding(.horizontal)
                    }

                    
                    Button {
                        let newDuplicate = createDuplicate()
                        modelContext.insert(newDuplicate)
                        duplicatedProtocol = newDuplicate
                        showDuplicateSheet = true
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.purple)
                    .padding(.horizontal)

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete Protocol", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.red)
                    .padding(.horizontal)
                    
                    Button {
                        shareProtocol()
                    } label: {
                        Label("Share Protocol", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.orange)
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditProtocolSheet = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showAddItemSheet) {
            AddProtocolItemSheet(therapyProtocol: therapyProtocol)
        }
        .sheet(isPresented: $showEditProtocolSheet) {
            EditProtocolSheet(therapyProtocol: .constant(therapyProtocol), isPresented: $showEditProtocolSheet)
        }
        .sheet(isPresented: $showDuplicateSheet) {
            if let duplicatedProtocol = duplicatedProtocol {
                EditProtocolSheet(therapyProtocol: .constant(duplicatedProtocol), isPresented: $showDuplicateSheet)
            }
        }
        .alert("Delete Protocol", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteProtocol() }
        }
        
        .sheet(isPresented: $showVerifySheet) {
            ProtocolVerificationView(protocol: therapyProtocol)
        }
    }

    private func deleteProtocolItem(_ item: TherapyProtocolItem) {
        withAnimation {
            therapyProtocol.items.removeAll { $0.id == item.id }
        }
        modelContext.delete(item)
        do {
            try modelContext.save()
        } catch {
            print("Error deleting protocol item: \(error)")
        }
    }

    private func markAsVerified() {
        if var tags = therapyProtocol.tags {
            tags.removeAll { $0 == "Web Source - Unverified" || $0 == "Requires Verification" }
            tags.append("Verified by User")
            therapyProtocol.tags = tags
            
            // Update notes if needed
            if let notes = therapyProtocol.notes, notes.contains("DISCLAIMER") {
                therapyProtocol.notes = notes.replacingOccurrences(of: "DISCLAIMER: This protocol was imported from the web and has not been medically verified.", with: "NOTE: This protocol was imported from the web and has been verified by the user.")
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Error marking protocol as verified: \(error)")
            }
        }
    }
    
    private func deleteProtocol() {
        modelContext.delete(therapyProtocol)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error deleting protocol: \(error)")
        }
    }

    private func createDuplicate() -> TherapyProtocol {
        let duplicatedProtocol = TherapyProtocol(
            title: "\(therapyProtocol.title) (Copy)",
            category: therapyProtocol.category,
            instructions: therapyProtocol.instructions,
            frequency: therapyProtocol.frequency,
            timeOfDay: therapyProtocol.timeOfDay,
            duration: therapyProtocol.duration,
            symptoms: therapyProtocol.symptoms ?? [],
            startDate: Date(),
            endDate: nil,
            notes: therapyProtocol.notes,
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: therapyProtocol.tags
        )

        for item in therapyProtocol.items {
            let duplicatedItem = TherapyProtocolItem(
                itemName: item.itemName,
                parentProtocol: duplicatedProtocol,
                dosageOrQuantity: item.dosageOrQuantity,
                usageNotes: item.usageNotes,
                cabinetItem: item.cabinetItem
            )
            duplicatedProtocol.items.append(duplicatedItem)
        }

        return duplicatedProtocol
    }
    
    private func shareProtocol() {
        let sharingService = ProtocolSharingService()
        
        // Share options
        let actionSheet = UIAlertController(title: "Share Protocol", message: "Choose how you want to share this protocol", preferredStyle: .actionSheet)
        
        // Share as text
        actionSheet.addAction(UIAlertAction(title: "Share Text", style: .default) { _ in
            let text = sharingService.exportProtocolAsText(therapyProtocol)
            let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = scene.windows.first?.rootViewController {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                rootVC.present(activityVC, animated: true)
            }
        })
        
        // Share as file
        actionSheet.addAction(UIAlertAction(title: "Export File", style: .default) { _ in
            if let fileURL = sharingService.exportProtocolToFile(therapyProtocol) {
                let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = scene.windows.first?.rootViewController {
                    activityVC.popoverPresentationController?.sourceView = rootVC.view
                    rootVC.present(activityVC, animated: true)
                }
            }
        })
        
        // Cancel option
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present the action sheet
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(actionSheet, animated: true)
        }
    }
}

// ✅ ProtocolItemsSection
struct ProtocolItemsSection: View {
    @Binding var isExpanded: Bool
    @Binding var therapyProtocol: TherapyProtocol
    var deleteAction: (TherapyProtocolItem) -> Void

    var body: some View {
        VStack {
            HStack {
                Text("Protocol Items")
                    .font(.headline)
                Spacer()
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            if isExpanded {
                if therapyProtocol.items.isEmpty {
                    Text("No items have been added to this protocol yet.")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.tertiarySystemFill))
                        .cornerRadius(10)
                        .padding(.horizontal)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(therapyProtocol.items, id: \.id) { item in
                            ProtocolItemCard(item: item, onTap: {
                                print("Tapped on \(item.itemName)")
                            })
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteAction(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
