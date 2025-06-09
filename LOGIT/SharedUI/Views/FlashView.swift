//
//  FlashView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 14.06.23.
//

import SwiftUI

struct FlashView: View {
    private let flashDuration = 0.1
    private let flashRepeatCount = 3

    let color: Color

    @Binding var shouldFlash: Bool

    @State private var isFlashing = false

    var body: some View {
        color
            .opacity(isFlashing ? 1 : 0)
            .onChange(of: shouldFlash) { newValue in
                guard newValue else { return }
                animateFlash(count: flashRepeatCount)
            }
    }

    private func animateFlash(count: Int) {
        if count <= 0 {
            isFlashing = false
            shouldFlash = false
            return
        }

        withAnimation(Animation.easeInOut(duration: flashDuration)) {
            isFlashing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration * 2) {
            withAnimation(Animation.easeInOut(duration: flashDuration)) {
                isFlashing = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) {
                animateFlash(count: count - 1)
            }
        }
    }
}

struct FlashView_Previews: PreviewProvider {
    static var previews: some View {
        FlashView(color: .accentColor, shouldFlash: .constant(true))
    }
}
