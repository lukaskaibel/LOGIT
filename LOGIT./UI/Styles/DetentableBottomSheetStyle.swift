//
//  DetentableBottomSheetStyle.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.05.25.
//

import SwiftUI

struct DetentableBottomSheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationBackgroundInteraction(.enabled)
            .presentationBackground(.thickMaterial)
            .presentationCornerRadius(30)
            .interactiveDismissDisabled()
    }
}

extension View {
    func detentableBottomSheetStyle() -> some View {
        modifier(DetentableBottomSheetStyle())
    }
}
