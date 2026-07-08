//
//  TrendIndicatorView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 10.06.26.
//

import SwiftUI

/// Capsule badge showing the percent change of a metric versus the previous period.
/// An upward trend uses the exercise's muscle-group color; a decline is muted gray with
/// a down arrow and no change is muted gray with no arrow at all — just the percent —
/// so a flat result is never mistaken for a decline. The same up/down semantic as the
/// set-delta arrows in the workout recorder.
struct TrendIndicatorView: View {
    let percentChange: Double
    var positiveColor: Color = .accentColor
    /// Optional style for the positive/record tint, taking precedence over `positiveColor` — the
    /// workout stat tiles pass the workout's multi-muscle-group gradient here, which a single
    /// `Color` can't carry. Decline and no change stay muted gray regardless.
    var positiveStyle: AnyShapeStyle? = nil
    /// While the value stands at a personal record the arrow gives way to a trophy, the percent to
    /// "PR", and the pill keeps the positive tint regardless of direction — a record is always a win,
    /// and a percentage beside a record has no baseline to be a percentage *of*.
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

    /// No arrow for a flat result — the muted gray percent carries the "no change"
    /// signal on its own, and an icon here would read like a decline.
    private var symbolName: String? {
        if isRecord { return "trophy.fill" }
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return nil
        }
    }

    private var displayedFraction: Double { Double(magnitude) / 100 }

    var body: some View {
        ProgressIndicatorPill(symbol: symbolName, style: tint) {
            // At a record the percent gives way to "PR" — beside the trophy a percentage reads as
            // "x % above what?" (the record has no higher baseline to beat), so the trophy + "PR"
            // says all there is to say. The percent returns the moment it's no longer a record.
            if isRecord {
                Text(NSLocalizedString("personalRecordShort", comment: ""))
                    .font(.system(.footnote, design: .rounded, weight: .bold))
            } else {
                Text(displayedFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
        }
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        // A record speaks its full name ("Personal record") rather than the percent the badge no
        // longer shows — VoiceOver and the badge stay in step.
        if isRecord { return Text(NSLocalizedString("personalRecord", comment: "")) }
        let percentString = displayedFraction.formatted(.percent.precision(.fractionLength(0)))
        switch direction {
        case .up:
            return Text(String(format: NSLocalizedString("trendUp", comment: ""), percentString))
        case .down:
            return Text(String(format: NSLocalizedString("trendDown", comment: ""), percentString))
        case .flat:
            return Text(NSLocalizedString("trendFlat", comment: ""))
        }
    }
}

struct TrendIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            TrendIndicatorView(percentChange: 12.5, positiveColor: .green)
            TrendIndicatorView(percentChange: -8.2, positiveColor: .green)
            TrendIndicatorView(percentChange: 0, positiveColor: .green)
            TrendIndicatorView(percentChange: 12.5, positiveColor: .green, isRecord: true)
        }
    }
}
