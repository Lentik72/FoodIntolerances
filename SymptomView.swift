// AddSymptomView.swift

import SwiftUI

struct AddSymptomView: View {
    @ObservedObject var viewModel: LogItemViewModel
    @Environment(\.dismiss) var dismiss
    @State private var newSymptomName: String = ""
    @State private var selectedIcon: String = "questionmark.circle"

    let availableIcons: [String] = [
        "head.brain", "wind", "bandage.fill", "stomach",
        "trash", "trash.fill", "mouth", "heart",
        "lungs.fill", "eyes", "nose", "ear",
        "hand.tap", "figure.walk", "heart.fill", "star.fill"
    ]

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Add New Symptom")
                    .font(.title2).bold()

                TextField("Symptom Name", text: $newSymptomName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.words)
                    .accessibilityLabel("Symptom Name")
                    .accessibilityHint("Enter the name of the new symptom")

                Text("Select an Icon")
                    .font(.headline)
                    .accessibilityLabel("Icon Selection")
                    .accessibilityHint("Choose an icon for the symptom")

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(availableIcons, id: \.self) { icon in
                        IconButton(icon: icon, isSelected: selectedIcon == icon) {
                            selectedIcon = icon
                        }
                        .accessibilityLabel("\(icon) Icon")
                        .accessibilityHint("Double tap to select this icon")
                    }
                }

                Button("Add Symptom") {
                    viewModel.addSymptom(newSymptomName)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newSymptomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add Symptom")
                .accessibilityHint("Double tap to add the new symptom")
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Symptom")
            .navigationBarItems(trailing: Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel Adding Symptom")
                .accessibilityHint("Double tap to cancel and dismiss the view"))
        }
    }
}

struct AddSymptomView_Previews: PreviewProvider {
    static var previews: some View {
        AddSymptomView(viewModel: LogItemViewModel())
    }
}
