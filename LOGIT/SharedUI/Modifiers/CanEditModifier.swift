//
//  CanEditModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 29.07.23.
//

import SwiftUI

struct CanEditModifier: ViewModifier {
    let canEdit: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.canEdit, canEdit)
    }
}

extension View {
    func canEdit(_ canEdit: Bool) -> some View {
        modifier(CanEditModifier(canEdit: canEdit))
    }
}
