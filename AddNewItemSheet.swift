// AddNewItemSheet.swift

import SwiftUI

struct AddNewItemSheet: View {
    @EnvironmentObject var viewModel: LogItemViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("New Item Details")) {
                    TextField("Item Name", text: $viewModel.newItemName)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .accessibilityLabel("New Item Name")
                        .accessibilityHint("Enter the name of the new category or symptom")
                    
                    Picker("Item Type", selection: $viewModel.newItemType) {
                        ForEach(LogItemViewModel.NewItemType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .accessibilityLabel("Item Type Picker")
                    .accessibilityHint("Select whether the new item is a category or symptom")
                }
                
                Section {
                    Button(action: {
                        viewModel.addNewItem()
                        dismiss()
                    }) {
                        Text("Add")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(viewModel.newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add New Item")
                    .accessibilityHint("Double tap to add the new item")
                }
            }
            .navigationTitle("Add New Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel Adding New Item")
                    .accessibilityHint("Double tap to cancel adding a new item")
                }
            }
        }
    }
}

struct AddNewItemSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddNewItemSheet()
            .environmentObject(LogItemViewModel())
    }
}
