//
//  StrengthTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import SwiftUI

// MARK: - Hero

/// The Strength headline: the trend arrow and its percent as one scaled-up `ProgressIndicatorPill`.
///
/// The pill is deliberate rather than decorative. `arrow.up` / `arrow.down` is the app's single
/// progress glyph and it lives inside this pill everywhere else — so the one surface whose entire
/// subject is that trend gets the same component, just at headline size. It also resolves a rule
/// conflict: values elsewhere stay neutral and the *pill* carries the accent, so a bare tinted
/// percent would break the convention while the same percent inside a pill is exactly where tinting
/// belongs. For a metric that is a ratio rather than a quantity, the pill simply *is* the value.
struct StrengthHeroPill: View {
    let percentChange: Double
    /// Scales the whole pill: the tile's headline vs the detail screen's larger one.
    var isCompact: Bool = false

    var body: some View {
        let color = strengthTrendColor(percentChange)
        ProgressIndicatorPill(
            symbol: strengthTrendSymbol(percentChange),
            color: color,
            size: .hero,
            symbolFont: .system(size: isCompact ? 22 : 26, weight: .bold)
        ) {
            Text(percentText)
                .font(.system(size: isCompact ? 30 : 35, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        // The pill never compresses: the movers beside it give way first.
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// One decimal, and no sign — the arrow carries the direction, exactly as the small trend pills
    /// do. A headline earns the decimal the compact pills round away.
    private var percentText: String {
        String(format: "%.1f%%", abs(percentChange))
    }

    private var accessibilityLabel: Text {
        let percent = (abs(percentChange) / 100).formatted(.percent.precision(.fractionLength(1)))
        if strengthTrendIsUp(percentChange) {
            return Text(String(format: NSLocalizedString("trendUp", comment: ""), percent))
        }
        if strengthTrendIsDown(percentChange) {
            return Text(String(format: NSLocalizedString("trendDown", comment: ""), percent))
        }
        return Text(NSLocalizedString("trendFlat", comment: ""))
    }
}

// MARK: - Tile

/// The Progress tab's headline tile: the hero pill states the whole-training trend, and the movers
/// beside it name the muscle groups carrying it — so the tile answers "how much" and "where from"
/// without a chart. Taps into `StrengthScreen`, which pulls the same weighted mean fully apart.
///
/// There is deliberately no sparkline: the metric is a percent change, and a chart of a rate over
/// time is both hard to read and nearly static (consecutive windows overlap almost entirely).
struct StrengthTile: View {
    let progress: StrengthProgress
    /// How many muscle groups the tile names beside the hero.
    var maxMovers: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let overall = progress.overallPercentChange {
                HStack(alignment: .center, spacing: 16) {
                    StrengthHeroPill(percentChange: overall, isCompact: true)
                    movers
                }
                .padding(.top, 13)
            } else {
                emptyState
                    .padding(.top, 12)
            }
        }
        .padding(CELL_PADDING)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(NSLocalizedString("strength", comment: ""))
                    .tileHeaderStyle()
                Spacer(minLength: 8)
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            Text(NSLocalizedString("strengthBasis", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The groups carrying the number, strongest first. Sorted by change rather than filtered to
    /// gains: if the top three are declines, that is the honest read and the pills grey themselves.
    private var movers: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(progress.groups.prefix(maxMovers)) { group in
                HStack(spacing: 8) {
                    Text(group.muscleGroup.description)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(group.muscleGroup.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    TrendIndicatorView(
                        percentChange: group.percentChange,
                        positiveColor: group.muscleGroup.color
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Before there's a trend, the tile wears the same gray ring the core-stat tiles use while their
    /// first period fills — the ring tracking how far the history reaches into the span being
    /// compared, so it creeps forward with every workout instead of sitting at nothing.
    private var emptyState: some View {
        TrendPlaceholder(
            progress: progress.historyFraction,
            text: NSLocalizedString("strengthEmpty", comment: ""),
            systemImage: "chart.line.uptrend.xyaxis",
            alignment: .leading,
            diameter: 34
        )
    }
}

struct StrengthTile_Previews: PreviewProvider {
    static var previews: some View {
        FetchRequestWrapper(Workout.self) { workouts in
            StrengthTile(progress: StrengthProgress.compute(workouts: workouts))
                .padding()
        }
        .previewEnvironmentObjects()
    }
}
