import SwiftUI

struct QuickNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""

    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $noteText)
                    .padding()
                    .border(Color.gray, width: 1)

                Button("Save Note") {
                    // Save logic here
                    dismiss()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .navigationTitle("Quick Note")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .padding()
        }
    }
}
