//
//  MetricComparisonView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.26.
//

import SwiftUI

/// A two-value comparison scoreboard: a neutral reference on the leading side, the tinted subject on
/// the trailing side, and the trend pill between them reading trailing against leading. The shared
/// shape behind the in-workout metric popover and every exercise / workout chart-detail header —
/// one home so the spelled-out values and the badge can never drift apart.
///
/// Color carries the meaning, exactly as in the in-workout popover it was lifted from: only the
/// trailing value wears the muscle-group tint (it's the subject — "you, now"), the leading reference
/// stays the neutral label color so a glance finds the subject. Each side optionally carries a
/// caption beneath its value (a date, a date range, a window name); the popover leaves them off, the
/// chart headers fill them with the period on screen. When `explanation` is set the pill becomes a
/// button presenting that text as a popover — the chart headers' "what is this?" affordance.
struct MetricComparisonView: View {
    struct Side {
        let label: String
        /// Pre-formatted value; the "––" placeholder is allowed.
        let value: String
        let unit: String
        /// Optional subtitle beneath the value — a date, a range, a window name. Nil hides it.
        var caption: String? = nil

        init(label: String, value: String, unit: String, caption: String? = nil) {
            self.label = label
            self.value = value
            self.unit = unit
            self.caption = caption
        }
    }

    /// The neutral reference (leading side).
    let leading: Side
    /// The subject (trailing side) — wears `trailingValueStyle`.
    let trailing: Side
    /// Style of the trailing value. Defaults to the neutral label color; pass a muscle-group
    /// `color.gradient` to tint the subject (the popover's live "you, now" side).
    var trailingValueStyle: AnyShapeStyle = AnyShapeStyle(Color.label)
    /// Percent of trailing over leading. Nil omits the pill — nothing to compare.
    let percentChange: Double?
    var positiveColor: Color = .accentColor
    var positiveStyle: AnyShapeStyle? = nil
    var isRecord: Bool = false
    /// When set, the pill becomes a button presenting this text as a popover.
    var explanation: String? = nil

    @State private var isShowingInfo = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Both sides claim an equal, flexible half of the row so the pill always lands in a
            // fixed center column. Without this the sides size to their content and the spacers
            // rebalance whenever a value's width changes (e.g. scrolling between data points),
            // which makes the pill drift off-center.
            side(leading, alignment: .leading, valueStyle: AnyShapeStyle(Color.label))
                .frame(maxWidth: .infinity, alignment: .leading)
            pill
            side(trailing, alignment: .trailing, valueStyle: trailingValueStyle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func side(_ side: Side, alignment: HorizontalAlignment, valueStyle: AnyShapeStyle) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(side.label)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            UnitView(value: side.value, unit: side.unit, configuration: .large)
                // One continuous gradient across value + unit, not one restarting in each.
                .continuousForegroundStyle(valueStyle)
            if let caption = side.caption {
                Text(caption)
                    .font(.caption)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var pill: some View {
        if let percentChange {
            let indicator = TrendIndicatorView(
                percentChange: percentChange,
                positiveColor: positiveColor,
                positiveStyle: positiveStyle,
                isRecord: isRecord
            )
            .animation(.snappy, value: percentChange)
            if let explanation {
                Button {
                    isShowingInfo = true
                } label: {
                    indicator
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingInfo) {
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .frame(width: 300)
                        .presentationCompactAdaptation(.popover)
                }
            } else {
                indicator
            }
        }
    }
}

struct MetricComparisonView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // Popover style: no captions, no explanation.
            MetricComparisonView(
                leading: .init(label: "Current Best", value: "100", unit: "kg"),
                trailing: .init(label: "This Workout", value: "105", unit: "kg"),
                trailingValueStyle: AnyShapeStyle(Color.green.gradient),
                percentChange: 5,
                positiveColor: .green
            )
            // Chart-header style: captions + tappable explanation.
            MetricComparisonView(
                leading: .init(label: "Best", value: "92", unit: "kg", caption: "25 May - 29 Jun"),
                trailing: .init(label: "Current Best", value: "105", unit: "kg", caption: "10 Jun"),
                trailingValueStyle: AnyShapeStyle(Color.green.gradient),
                percentChange: 14,
                positiveColor: .green,
                explanation: "Current best (right) is your highest value in the last 4 weeks."
            )
        }
        .padding()
    }
}
