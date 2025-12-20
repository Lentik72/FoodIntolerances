import SwiftUI

struct BodyMapSelectionView: View {
    @Binding var selectedAreas: [String]
    
    let bodyAreas = [
        "head",
        "neck", 
        "chest",
        "abdomen",
        "pelvic",
        "upperLeftArm",
        "lowerLeftArm",
        "upperRightArm",
        "lowerRightArm",
        "upperLeftLeg",
        "lowerLeftLeg",
        "upperRightLeg",
        "lowerRightLeg",
        "upperBack",
        "middleBack",
        "lowerBack"
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 10) {
                ForEach(bodyAreas, id: \.self) { area in
                    Toggle(area.capitalized, isOn: Binding(
                        get: { selectedAreas.contains(area) },
                        set: { isSelected in
                            if isSelected {
                                selectedAreas.append(area)
                            } else {
                                selectedAreas.removeAll { $0 == area }
                            }
                        }
                    ))
                }
            }
            .padding()
        }
        .frame(maxHeight: 200)
    }
}
