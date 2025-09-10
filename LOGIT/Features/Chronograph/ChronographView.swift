//
//  ChronographView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 09.07.25.
//

import SwiftUI

struct ChronographView<Content: View>: View {
    @ObservedObject var chronograph: Chronograph
    let content: (_ remainingSeconds: Double) -> Content

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    @State private var seconds: Double = 120

    var body: some View {
        content(seconds)
            .onAppear {
                seconds = chronograph.seconds
            }
            .onReceive(timer) { _ in
                seconds = chronograph.seconds
            }
            .onReceive(chronograph.objectWillChange) { _ in
                seconds = chronograph.seconds
            }
    }
}

private struct ChronographViewPreviewWrapper: View {
    @StateObject private var chronograph = Chronograph()

    var body: some View {
        ChronographView(chronograph: chronograph) { remainingSeconds in
            Text("\(remainingSeconds)")
        }
        .onAppear {
            chronograph.mode = .timer
            chronograph.setSeconds(120)
            chronograph.start()
        }
    }
}

#Preview {
    ChronographViewPreviewWrapper()
}
