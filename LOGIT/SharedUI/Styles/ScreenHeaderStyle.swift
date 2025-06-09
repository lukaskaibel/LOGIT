//
//  ScreenHeaderStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 14.08.23.
//

import SwiftUI

struct ScreenHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.largeTitle.weight(.bold))
    }
}

struct ScreenHeaderSecondaryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.title2, design: .rounded, weight: .semibold))
    }
}

struct ScreenHeaderTertiaryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textCase(.uppercase)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
    }
}

extension View {
    func screenHeaderStyle() -> some View {
        modifier(ScreenHeaderModifier())
    }

    func screenHeaderSecondaryStyle() -> some View {
        modifier(ScreenHeaderSecondaryModifier())
    }

    func screenHeaderTertiaryStyle() -> some View {
        modifier(ScreenHeaderTertiaryModifier())
    }
}

struct ScreenHeaderStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            Text("Tertiary Text")
                .screenHeaderTertiaryStyle()
            Text("Hello World")
                .screenHeaderStyle()
            Text("Secondary Text")
                .screenHeaderSecondaryStyle()
        }
    }
}
