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

/// The Summary's Strength half: the trend as a headline figure, and beneath it every trained
/// exercise as one ranked bar. Half width, paired with `MuscleBalanceGoalTile` — the two are
/// deliberately the same shape (a field of vertical bars on a shared baseline) so the top of the
/// screen reads as one component rather than two unrelated cards.
///
/// The chart runs to the bottom edge with no caption under it. What that costs is stated plainly:
/// nothing on the tile says the bars are *ranked* rather than chronological. `StrengthScreen`
/// corrects that on the first tap, and the ramp climbing left to right does most of the work.
struct StrengthTile: View {
    let progress: StrengthProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            subtitle
                .padding(.top, 8)
            if let overall = progress.overallPercentChange {
                hero(overall)
                    .padding(.top, 2)
                StrengthBarChart(changes: progress.changes)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 12)
            } else {
                emptyState
                    .padding(.top, 12)
                Spacer(minLength: 0)
            }
        }
        .padding(CELL_PADDING)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString("strength", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            NavigationChevron()
                .foregroundStyle(Color.secondaryLabel)
        }
    }

    private var subtitle: some View {
        Text(NSLocalizedString("strengthBasis", comment: ""))
            .font(.caption.weight(.medium))
            .tracking(0.3)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Arrow plus percent, both in the trend colour. The scaled-up `StrengthHeroPill` doesn't fit a
    /// half-width tile beside the chart, and the chart below already carries the accent — so here
    /// the figure wears it directly and the pill keeps its place on the detail screen's hero.
    private func hero(_ percent: Double) -> some View {
        // Centred, not baseline-aligned: a glyph on a text baseline hangs low beside a 30 pt figure.
        HStack(alignment: .center, spacing: 3) {
            Image(systemName: strengthTrendSymbol(percent))
                .font(.system(size: 15, weight: .black))
            Text(String(format: "%.1f%%", abs(percent)))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .foregroundStyle(strengthTrendColor(percent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel(percent))
    }

    private func heroAccessibilityLabel(_ percent: Double) -> Text {
        let value = (abs(percent) / 100).formatted(.percent.precision(.fractionLength(1)))
        if strengthTrendIsUp(percent) {
            return Text(String(format: NSLocalizedString("trendUp", comment: ""), value))
        }
        if strengthTrendIsDown(percent) {
            return Text(String(format: NSLocalizedString("trendDown", comment: ""), value))
        }
        return Text(NSLocalizedString("trendFlat", comment: ""))
    }

    /// Before there's a trend, the tile wears the same gray ring the core-stat tiles use while their
    /// first period fills — tracking how far the history reaches into the span being compared, so it
    /// creeps forward with every workout instead of sitting at nothing.
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
