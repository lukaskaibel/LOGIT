//
//  TrendIndicatorView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 10.06.26.
//

import SwiftUI

/// Capsule badge showing the percent change of a metric versus the previous period.
/// An upward trend uses the exercise's muscle-group color; a decline is muted gray with
/// a down chevron and no change is muted gray with no chevron at all — just the percent —
/// so a flat result is never mistaken for a decline. The same up/down semantic as the
/// set-delta chevrons in the workout recorder.
struct TrendIndicatorView: View {
    let percentChange: Double
    var positiveColor: Color = .accentColor
    /// Optional style for the positive/record tint, taking precedence over `positiveColor` — the
    /// workout stat tiles pass the workout's multi-muscle-group gradient here, which a single
    /// `Color` can't carry. Decline and no change stay muted gray regardless.
    var positiveStyle: AnyShapeStyle? = nil
    /// While the value stands at a personal record the chevron gives way to a trophy and the pill
    /// keeps the positive tint regardless of direction — a record is always a win.
    var isRecord: Bool = false

    private enum Direction { case up, down, flat }

    /// Displayed magnitude as an integer percent, capped so tiny baselines don't
    /// produce absurdly wide badges. Anything that rounds to 0 reads as no change.
    private var magnitude: Int { Int(min(abs(percentChange), 999).rounded()) }

    private var direction: Direction {
        guard magnitude > 0 else { return .flat }
        return percentChange > 0 ? .up : .down
    }

    /// Only a genuine improvement (or a record) is tinted; decline and no change stay muted gray.
    private var isPositive: Bool { isRecord || direction == .up }

    /// The pill's tint for text and capsule — the supplied positive style (else color) while
    /// positive, muted gray otherwise. An `AnyShapeStyle` so a gradient can stand in for the color.
    private var tint: AnyShapeStyle {
        guard isPositive else { return AnyShapeStyle(Color.secondary) }
        return positiveStyle ?? AnyShapeStyle(positiveColor)
    }

    /// No chevron for a flat result — the muted gray percent carries the "no change"
    /// signal on its own, and an icon here would read like a decline.
    private var symbolName: String? {
        if isRecord { return "trophy.fill" }
        switch direction {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .flat: return nil
        }
    }

    private var displayedFraction: Double { Double(magnitude) / 100 }

    var body: some View {
        HStack(spacing: 4) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.bold))
            }
            Text(displayedFraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.15)))
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        let percentString = displayedFraction.formatted(.percent.precision(.fractionLength(0)))
        let trend: String
        switch direction {
        case .up:
            trend = String(format: NSLocalizedString("trendUp", comment: ""), percentString)
        case .down:
            trend = String(format: NSLocalizedString("trendDown", comment: ""), percentString)
        case .flat:
            trend = NSLocalizedString("trendFlat", comment: "")
        }
        guard isRecord else { return Text(trend) }
        return Text("\(NSLocalizedString("personalRecord", comment: "")), \(trend)")
    }
}

struct TrendIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            TrendIndicatorView(percentChange: 12.5, positiveColor: .green)
            TrendIndicatorView(percentChange: -8.2, positiveColor: .green)
            TrendIndicatorView(percentChange: 0, positiveColor: .green)
        }
    }
}
