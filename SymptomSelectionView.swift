//
//  SymptomSelectionView.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 1/29/25.
//

// SymptomSelectionView.swift

import SwiftUI


// MARK: - SearchBarView

struct SearchBarView: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            
            TextField("Search symptoms...", text: $searchText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .accessibilityLabel("Clear Search Text")
                .accessibilityHint("Double tap to clear the search field")
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
