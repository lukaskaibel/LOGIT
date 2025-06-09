//
//  NoDataPlaceholderModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

struct NoDataPlaceholderModifier<Items: Collection>: ViewModifier {
    let items: Items
    let placeholder: AnyView

    @ViewBuilder func body(content: Content) -> some View {
        if !items.isEmpty {
            content
        } else {
            placeholder
                .font(.title3)
                .foregroundColor(.placeholder)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
        }
    }
}

extension View {
    func noDataPlaceholder<Items: Collection, PlaceholderView: View>(
        _ items: Items,
        _ placeholder: @escaping () -> PlaceholderView
    ) -> some View {
        modifier(NoDataPlaceholderModifier(items: items, placeholder: AnyView(placeholder())))
    }
}
