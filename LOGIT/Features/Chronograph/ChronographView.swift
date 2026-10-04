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

    var body: some View {
        // Ticks ten times a second while the clock runs, and not at all otherwise: a paused or idle
        // chronograph shows nothing that moves, and the timer this replaces re-rendered the floating
        // button ten times a second for the whole workout, keeping the main thread awake for nothing.
        // Starting, stopping and adjusting the clock all publish, which redraws it straight away.
        TimelineView(ChronographTicks(isRunning: chronograph.status == .running)) { _ in
            content(chronograph.seconds)
        }
    }
}

/// Every tenth of a second while running; a single entry — no ticks — otherwise.
private struct ChronographTicks: TimelineSchedule {
    let isRunning: Bool

    func entries(from startDate: Date, mode _: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        let isRunning = isRunning
        return AnyIterator {
            guard let current = next else { return nil }
            next = isRunning ? current.addingTimeInterval(0.1) : nil
            return current
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
