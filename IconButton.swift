//
//  IconButton.swift
//  Food Intolerances
//
//  Created by Leo on [Date].
//

import SwiftUI

struct IconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(isSelected ? .blue : .gray)

                Text(icon.replacingOccurrences(of: ".", with: " ").capitalized)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IconButton_Previews: PreviewProvider {
    static var previews: some View {
        IconButton(icon: "head.brain", isSelected: true, action: {})
    }
}
