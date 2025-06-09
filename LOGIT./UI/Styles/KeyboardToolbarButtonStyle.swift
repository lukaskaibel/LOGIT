//
//  KeyboardToolbarButtonStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

struct KeyboardToolbarButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.light))
            .foregroundColor(.primary)
            .frame(width: 70)
    }
}

extension View {
    func keyboardToolbarButtonStyle() -> some View {
        modifier(KeyboardToolbarButtonModifier())
    }
}
