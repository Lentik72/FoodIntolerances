//
//  PrimaryButtonStyle.swift
//  Food Intolerances
//
//  Created by Leo on [Date].
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(configuration.isPressed ? Color.blue.opacity(0.6) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct PrimaryButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        Button("Primary Button") { }
            .buttonStyle(PrimaryButtonStyle())
    }
}
