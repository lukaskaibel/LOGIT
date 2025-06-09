//
//  SectionHeaderStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 27.07.23.
//

import SwiftUI

struct SectionHeaderModifier2: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title2.weight(.bold))
            .foregroundColor(.label)
    }
}

struct SectionHeaderSecondaryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundColor(.secondaryLabel)
    }
}

extension View {
    func sectionHeaderStyle2() -> some View {
        modifier(SectionHeaderModifier2())
    }

    func sectionHeaderSecondaryStyle() -> some View {
        modifier(SectionHeaderSecondaryModifier())
    }
}

struct SectionHeaderStyle_Previews: PreviewProvider {
    static var previews: some View {
        Text("Hello World")
            .sectionHeaderStyle2()
        Text("Secondary Text")
            .sectionHeaderSecondaryStyle()
    }
}
