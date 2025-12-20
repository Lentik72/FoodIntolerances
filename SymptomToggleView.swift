//
//  SymptomToggleView.swift
//  Food Intolerances
//
//  Created by Leo on [Date].
//

import SwiftUI

struct SymptomToggleView: View {
    let symptom: String
    @Binding var selectedSymptoms: [String]

    var body: some View {
        Toggle(symptom, isOn: Binding(
            get: { selectedSymptoms.contains(symptom) },
            set: { newValue in
                if newValue {
                    selectedSymptoms.append(symptom)
                } else {
                    selectedSymptoms.removeAll { $0 == symptom }
                }
            }
        ))
    }
}

struct SymptomToggleView_Previews: PreviewProvider {
    static var previews: some View {
        SymptomToggleView(symptom: "Headache", selectedSymptoms: .constant(["Headache"]))
    }
}
