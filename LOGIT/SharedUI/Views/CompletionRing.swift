//
//  CompletionRing.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The app's single progress ring: a faint full-circle track with a rounded-cap arc trimmed to
/// `progress`, optionally wrapping a centered label. One ring for the weekly-goal hero, the goal
/// screen's per-week rings, and the goal screen's year-band per-month rings — so the cap shape, track
/// tint and sweep direction stay identical everywhere.
struct CompletionRing<Label: View>: View {
    /// Completion 0…1; values outside are clamped.
    let progress: Double
    var lineWidth: CGFloat = 8
    /// The arc's tint — a flat muscle color or the accent; drawn with its subtle `.gradient`.
    var color: Color = .accentColor
    var trackColor: Color = .fill
    @ViewBuilder var label: () -> Label

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: clampedProgress)
            label()
        }
    }
}

extension CompletionRing where Label == EmptyView {
    /// A bare ring with no centered content — the small per-week / per-month rings.
    init(
        progress: Double,
        lineWidth: CGFloat = 8,
        color: Color = .accentColor,
        trackColor: Color = .fill
    ) {
        self.init(
            progress: progress,
            lineWidth: lineWidth,
            color: color,
            trackColor: trackColor,
            label: { EmptyView() }
        )
    }
}

#Preview {
    HStack(spacing: 20) {
        CompletionRing(progress: 0.66)
            .frame(width: 80, height: 80)
        CompletionRing(progress: 0.4, color: MuscleGroup.legs.color) {
            Text("2/5")
                .font(.headline)
                .fontDesign(.rounded)
        }
        .frame(width: 80, height: 80)
        CompletionRing(progress: 1.0, color: .green)
            .frame(width: 40, height: 40)
    }
    .padding()
}
