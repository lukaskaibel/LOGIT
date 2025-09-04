//
//  TileHeaderStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 22.08.23.
//

import SwiftUI

struct TileHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.semibold))
            .foregroundColor(.label)
    }
}

struct TileHeaderSecondaryModifier: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        content
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundColor(color ?? .secondaryLabel)
    }
}

struct TileHeaderTertiaryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.secondaryLabel)
    }
}

extension View {
    func tileHeaderStyle() -> some View {
        modifier(TileHeaderModifier())
    }

    func tileHeaderSecondaryStyle(color: Color? = nil) -> some View {
        modifier(TileHeaderSecondaryModifier(color: color))
    }

    func tileHeaderTertiaryStyle() -> some View {
        modifier(TileHeaderTertiaryModifier())
    }
}
