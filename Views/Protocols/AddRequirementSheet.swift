//
//  AddRequirementSheet.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 2/1/25.
//

import SwiftUI
import SwiftData

struct AddRequirementSheet: View {
    @Environment(\.modelContext) private var modelContext
    
    var protocolItem: TherapyProtocol
    
    @Binding var isPresented: Bool
    
    @Binding var newItemName: String
    @Binding var selectedCabinetItem: CabinetItem?
    @Binding var dosage: String
    @Binding var requirementNotes: String
    
    /// For searching/ picking items from the cabinet
    @Query(sort: \CabinetItem.name, order: .forward)
    private var cabinetItems: [CabinetItem]
    
    /// If we want to let user pick from an existing cabinet item or enter custom name
    @State private var useCabinetItem: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Requirement Source") {
                    Toggle("Pick from Cabinet?", isOn: $useCabinetItem)
                }
                if useCabinetItem {
                    Picker("Select Cabinet Item", selection: $selectedCabinetItem) {
                        Text("None").tag(CabinetItem?.none)
                        ForEach(cabinetItems) { item in
                            Text(item.name).tag(CabinetItem?.some(item))
                        }
                    }
                } else {
                    TextField("Custom Item Name", text: $newItemName)
                }
                
                Section("Details") {
                    TextField("Dosage (e.g. 1 tsp, 200 mg)", text: $dosage)
                    TextField("Notes", text: $requirementNotes)
                }
                
                Section {
                    Button("Add") {
                        addRequirement()
                    }
                    .disabled(!useCabinetItem && newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Add Requirement")
        }
    }
    
    private func addRequirement() {
        let finalName: String
        if useCabinetItem, let cab = selectedCabinetItem {
            finalName = cab.name
        } else {
            finalName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !finalName.isEmpty else { return }
        
        let requirement = ProtocolRequirement(
            itemName: finalName,
          //  parentProtocol: protocolItem,
            dosage: dosage,
            notes: requirementNotes
        )
        
        if useCabinetItem, let cab = selectedCabinetItem {
            requirement.cabinetItem = cab
        }
        
        modelContext.insert(requirement)
        
        do {
            try modelContext.save()
            clearFields()
            dismiss()
        } catch {
            Logger.error(error, message: "Error saving requirement", category: .data)
        }
    }
    
    private func clearFields() {
        newItemName = ""
        dosage = ""
        requirementNotes = ""
        selectedCabinetItem = nil
        useCabinetItem = false
    }
    
    private func dismiss() {
        isPresented = false
    }
}
