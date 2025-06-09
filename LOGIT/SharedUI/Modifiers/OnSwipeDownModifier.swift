//
//  OnSwipeDownModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

struct OnSwipeDownModifier: ViewModifier {
    let onSwipeDown: () -> Void

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    let swipeDistance = value.translation.height
                    if swipeDistance > 0 {
                        onSwipeDown()
                    }
                }
        )
    }
}

extension View {
    func onSwipeDown(perform action: @escaping () -> Void) -> some View {
        modifier(OnSwipeDownModifier(onSwipeDown: action))
    }
}
