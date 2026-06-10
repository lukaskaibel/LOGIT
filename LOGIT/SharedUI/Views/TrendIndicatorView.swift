//
//  TrendIndicatorView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 10.06.26.
//

import SwiftUI

/// Capsule badge showing the percent change of a metric versus the previous period.
/// An upward trend uses the exercise's muscle-group color, a downward trend is muted
/// gray — the same semantic as the set-delta chevrons in the workout recorder.
struct TrendIndicatorView: View {
    let percentChange: Double
    var positiveColor: Color = .accentColor

    private var isUp: Bool { percentChange >= 0 }
    private var color: Color { isUp ? positiveColor : .secondary }
    /// Capped so tiny baselines don't produce absurdly wide badges.
    private var displayedFraction: Double { min(abs(percentChange), 999) / 100 }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isUp ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
            Text(displayedFraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.15)))
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: NSLocalizedString(isUp ? "trendUp" : "trendDown", comment: ""),
                displayedFraction.formatted(.percent.precision(.fractionLength(0)))
            )
        )
    }
}

struct TrendIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            TrendIndicatorView(percentChange: 12.5, positiveColor: .green)
            TrendIndicatorView(percentChange: -8.2, positiveColor: .green)
            TrendIndicatorView(percentChange: 0, positiveColor: .blue)
        }
    }
}
