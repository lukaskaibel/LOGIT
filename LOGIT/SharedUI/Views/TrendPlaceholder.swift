//
//  TrendPlaceholder.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import SwiftUI

/// The placeholder a tile shows before it has a trend to draw — a quiet gray progress ring around a
/// small glyph, beside a line of copy, sitting where the data would. All gray, no accent: it's a
/// nudge, not data — the honest answer to "there's nothing to chart yet" without faking a chart.
///
/// The ring tracks how far along the wait is (how far through the period, or how much history has
/// accumulated), so it creeps forward instead of sitting at a fixed mark. **It never renders as a
/// bare track**: the fill floors at `minimumFill`, so a brand-new tile reads as *started* rather
/// than as a broken or empty control.
///
/// Shared by the Summary's core-stat tiles and the Strength tile so "not enough data yet" looks the
/// same wherever it appears.
struct TrendPlaceholder: View {
    /// How far along the wait is, 0…1. Values outside are clamped; zero still shows `minimumFill`.
    let progress: Double
    let text: String
    var systemImage: String = "chart.bar.fill"
    /// Where the placeholder sits in the space it's given — the stat tiles anchor it to the bottom
    /// of their chart slot; the Strength tile centres it vertically in a text row.
    var alignment: Alignment = .bottomLeading
    var diameter: CGFloat = 30

    /// Even at zero the ring keeps this much arc, so it reads as begun rather than empty.
    private static let minimumFill = 0.05

    private var fill: Double { min(max(progress, Self.minimumFill), 1) }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(Color.fill, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(Color.secondaryLabel, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    // Start at 12 o'clock and fill clockwise, like every other progress ring.
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fill)
                Image(systemName: systemImage)
                    .font(.system(size: diameter / 3))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: diameter, height: diameter)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                // Three lines: the half-width Summary tiles are narrow enough that two truncated
                // this copy mid-word.
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 24) {
        TrendPlaceholder(progress: 0, text: "Building your trend")
        TrendPlaceholder(progress: 0.4, text: "Building your trend")
        TrendPlaceholder(
            progress: 0.15,
            text: "Keep logging workouts to see your strength trend.",
            systemImage: "chart.line.uptrend.xyaxis",
            alignment: .leading
        )
    }
    .padding()
}
