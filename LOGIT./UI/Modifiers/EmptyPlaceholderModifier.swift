//
//  EmptyPlaceholderModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

struct EmptyPlaceholderModifier<Items: Collection>: ViewModifier {
    let items: Items
    let placeholder: AnyView

    @ViewBuilder func body(content: Content) -> some View {
        if !items.isEmpty {
            content
        } else {
            placeholder
                .font(.title2)
                .foregroundColor(.placeholder)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

extension View {
    func emptyPlaceholder<Items: Collection, PlaceholderView: View>(
        _ items: Items,
        _ placeholder: @escaping () -> PlaceholderView
    ) -> some View {
        modifier(EmptyPlaceholderModifier(items: items, placeholder: AnyView(placeholder())))
    }
}
