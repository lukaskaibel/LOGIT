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
/// # One size, everywhere
///
/// Every metric of this view is fixed here rather than passed in: the ring's diameter, its stroke,
/// the glyph size, the type, and where the whole thing anchors in the space it's given. Callers vary
/// only the two things that are genuinely *content* — the progress the ring reports and the line of
/// copy, plus the glyph that names which metric is waiting.
///
/// It used to take `diameter` and `alignment`, and the four call sites had drifted to three
/// different ring sizes and two anchors, so the same "no data yet" state was visibly a different
/// component on each surface. The type had drifted too, less obviously: `minimumScaleFactor` meant
/// the caption silently shrank to whatever the narrowest tile could fit, so two tiles side by side
/// rendered the same style at different sizes. The copy now wraps instead of shrinking, which keeps
/// one type size across every surface at the cost of a taller block in narrow tiles — and since the
/// placeholder stands in for a chart that runs to the bottom edge, it grows upward into slack that
/// was empty anyway.
struct TrendPlaceholder: View {
    /// How far along the wait is, 0…1. Values outside are clamped; zero still shows `minimumFill`.
    let progress: Double
    let text: String
    /// Which metric is waiting — the only visual difference between one placeholder and the next.
    var systemImage: String = "chart.bar.fill"

    /// Even at zero the ring keeps this much arc, so it reads as begun rather than empty.
    private static let minimumFill = 0.05
    /// Sized for the half-width Summary tiles, which are the tightest place it appears; the detail
    /// screens have more room but don't get a bigger one, because then it wouldn't be the same thing.
    private static let diameter: CGFloat = 34
    private static let lineWidth: CGFloat = 3

    private var fill: Double { min(max(progress, Self.minimumFill), 1) }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(Color.fill, lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(
                        Color.secondaryLabel,
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                    )
                    // Start at 12 o'clock and fill clockwise, like every other progress ring.
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fill)
                Image(systemName: systemImage)
                    .font(.system(size: Self.diameter / 3))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                // Wraps as far as it needs to. No line cap and no minimum scale: either would trade
                // this view's one guarantee — that it looks identical everywhere — for a fit that
                // vertical slack can give it for free.
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // Bottom-anchored: it stands in for a chart that runs to the bottom edge, so it sits where
        // the chart's baseline would rather than floating in the middle of the slack.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    // Half-width, the tightest case: both tiles of the Summary's top pair, side by side, plus the
    // core-stat tile's shorter copy. Same ring, same type, whatever the line count works out to.
    VStack(spacing: 24) {
        HStack(alignment: .top, spacing: 10) {
            TrendPlaceholder(
                progress: 0.15,
                text: "Keep logging workouts to see your strength trend.",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            TrendPlaceholder(
                progress: 0,
                text: "Keep training to see your muscle split",
                systemImage: "chart.pie.fill"
            )
        }
        .frame(height: 110)
        HStack(alignment: .top, spacing: 10) {
            TrendPlaceholder(progress: 0.4, text: "Building your trend")
            TrendPlaceholder(progress: 1, text: "Building your trend")
        }
        .frame(height: 70)
        TrendPlaceholder(
            progress: 0.15,
            text: "Keep logging workouts to see your strength trend.",
            systemImage: "chart.line.uptrend.xyaxis"
        )
        .frame(height: 50)
    }
    .padding()
}
