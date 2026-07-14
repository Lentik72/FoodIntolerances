import SwiftUI
import HealthGraphCore

struct EventEditView: View {
    let original: HealthEvent
    @ObservedObject var viewModel: TimelineViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var timestamp: Date
    @State private var name: String
    @State private var severity: Double
    @State private var amountText: String

    init(event: HealthEvent, viewModel: TimelineViewModel) {
        self.original = event; self.viewModel = viewModel
        _timestamp = State(initialValue: event.timestamp)
        // Symptoms store a canonical camelCase key — show the human display name for editing.
        // Qualified explicitly: the app target also has a legacy (pre-pivot) `SymptomCatalog` /
        // `SymptomDefinition` type at its root, which would otherwise shadow HealthGraphCore's.
        _name = State(initialValue: event.category == .symptom
                      ? HealthGraphCore.SymptomCatalog.displayName(for: event.subtype ?? "")
                      : (event.subtype ?? ""))
        _severity = State(initialValue: event.value ?? 5)
        _amountText = State(initialValue: event.value.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "")
    }

    private var isSymptom: Bool { original.category == .symptom }
    private var isDose: Bool { [.medication, .supplement, .peptide].contains(original.category) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("When", selection: $timestamp, in: ...Date()).datePickerStyle(.compact)
                    TextField("Name", text: $name).padding(12).hgCard()
                    if isSymptom {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Severity: \(Int(severity))").font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
                            Slider(value: $severity, in: 1...10, step: 1).tint(CategoryFamily.symptoms.color)
                        }
                    } else if isDose {
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad).padding(12).hgCard()
                    }
                }
                .padding(16)
            }
            .background(HealthTheme.paper)
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        var edited = original
        edited.timestamp = timestamp
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Re-canonicalize a symptom name so the edited event stays in its severity series.
        edited.subtype = isSymptom ? HealthGraphCore.SymptomCatalog.canonicalKey(for: trimmedName) : trimmedName
        if isSymptom { edited.value = severity; edited.unit = "severity" }
        else if isDose { edited.value = Double(amountText.replacingOccurrences(of: ",", with: ".")) }
        if await viewModel.update(edited) { dismiss() }
    }
}
