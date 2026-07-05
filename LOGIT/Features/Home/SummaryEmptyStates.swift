//
//  SummaryEmptyStates.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// MARK: - Pinned exercises empty state

/// Shown in the Summary's pinned-exercises section when nothing is pinned: two dimmed sample tiles
/// behind a "Pin your key lifts" call-to-action. The samples are the real `MetricTile` rendered
/// with made-up numbers, so they always match the current pinned-tile design. They double as a Pro
/// teaser, since the marquee metrics they show (Est. 1RM, volume) are exactly what's gated. Replaces
/// the old gray tip card.
struct PinnedExercisesEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                SampleExerciseTile(
                    name: "Bench Press",
                    value: "102",
                    percentChange: 4.2,
                    color: MuscleGroup.chest.color,
                    points: [0.35, 0.5, 0.45, 0.7, 1.0]
                )
                SampleExerciseTile(
                    name: "Squat",
                    value: "145",
                    percentChange: 2.8,
                    color: MuscleGroup.legs.color,
                    points: [0.4, 0.55, 0.5, 0.8, 1.0]
                )
            }
            .opacity(0.3)
            .allowsHitTesting(false)
            callToAction(title: NSLocalizedString("pinKeyLifts", comment: ""), buttonTitle: NSLocalizedString("chooseExercises", comment: ""), onAdd: onAdd)
        }
    }
}

// MARK: - Measurements empty state

/// The measurements echo of the pinned teaser — two dimmed sample watchlist rows in a single card
/// (the same dimming as the pinned tiles) behind a "Track your measurements" call-to-action, so the
/// two sections read as one family.
struct MeasurementsEmptyState: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    let onAdd: () -> Void
    @State private var isShowingUpgrade = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ghostRow(icon: "scalemass", name: NSLocalizedString("bodyweight", comment: ""), value: "78.4", unit: WeightUnit.used.rawValue, points: [0.75, 0.55, 0.6, 0.4, 0.45, 0.3])
                Divider()
                ghostRow(icon: "percentage", name: NSLocalizedString("bodyFatPercentage", comment: ""), value: "14.2", unit: "%", points: [0.85, 0.7, 0.6, 0.5, 0.4, 0.35])
            }
            .padding(.horizontal, CELL_PADDING)
            .tileStyle()
            .opacity(0.3)
            .allowsHitTesting(false)
            VStack(spacing: 12) {
                Text(NSLocalizedString("trackMeasurements", comment: ""))
                    .font(.headline)
                    .foregroundStyle(Color.label)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                // Measurements are a Pro feature: a free user can't pin, so the empty state is the
                // upgrade hook — a clean teaser + "Unlock with Pro" rather than a blurred section.
                if purchaseManager.hasUnlockedPro {
                    SummaryPillButton(title: NSLocalizedString("pinAMeasurement", comment: ""), systemImage: "plus", action: onAdd)
                } else {
                    SummaryPillButton(title: NSLocalizedString("unlockWithPro", comment: ""), systemImage: "crown.fill") {
                        isShowingUpgrade = true
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingUpgrade) {
            NavigationStack { UpgradeToProScreen() }
        }
    }

    private func ghostRow(icon: String, name: String, value: String, unit: String, points: [CGFloat]) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text(NSLocalizedString("current", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            GhostTrendLine(points: points, color: .secondary)
                .frame(width: 50, height: 22)
            UnitView(value: value, unit: unit, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Shared pieces

/// The centered headline + accent pill overlaid on a dimmed sample — the shared call-to-action both
/// empty states wear.
private func callToAction(title: String, buttonTitle: String, onAdd: @escaping () -> Void) -> some View {
    VStack(spacing: 12) {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.label)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.6), radius: 8)
        SummaryPillButton(title: buttonTitle, systemImage: "plus", action: onAdd)
    }
}

/// A dimmed sample of a pinned exercise tile: the real `MetricTile` with the real tile sparkline,
/// rendered from made-up numbers — deliberately not a hand-drawn replica, so a tile redesign can
/// never leave this preview showing the old look. Same anatomy as `ExerciseBestMetricTile`, with
/// the exercise name in the title slot and the metric as the subtitle so the preview reads as
/// "your key lifts".
private struct SampleExerciseTile: View {
    let name: String
    let value: String
    let percentChange: Double
    let color: Color
    /// Normalized 0…1 progression, oldest → newest, laid out weekly across the current-best window.
    let points: [Double]

    var body: some View {
        MetricTile(
            title: name,
            label: .plain(NSLocalizedString("estimatedOneRepMax", comment: "")),
            value: value,
            unit: WeightUnit.used.rawValue,
            accent: AnyShapeStyle(color),
            accentColor: color,
            percentChange: percentChange
        ) {
            ExerciseTileSparkline(
                points: samplePoints,
                color: color,
                window: .currentBest,
                bleeds: true
            )
        }
    }

    /// The normalized progression on real dates — one point a week, newest today — so the sparkline
    /// plots inside the same current-best window a real pinned tile shows.
    private var samplePoints: [ExerciseTileSparkline.Point] {
        points.enumerated().map { index, value in
            let daysAgo = (points.count - 1 - index) * 7
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            return ExerciseTileSparkline.Point(date: date, value: value)
        }
    }
}

/// A simple rounded-cap line through normalized 0…1 points — the sample sparkline on the
/// measurements empty state's ghost rows.
private struct GhostTrendLine: View {
    let points: [CGFloat]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let w = geometry.size.width
                let h = geometry.size.height
                for (index, value) in points.enumerated() {
                    let x = w * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let y = h * (1 - value)
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A compact accent pill button — the call-to-action on the Summary empty states.
struct SummaryPillButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 24) {
        PinnedExercisesEmptyState(onAdd: {})
        MeasurementsEmptyState(onAdd: {})
    }
    .padding()
    .previewEnvironmentObjects()
}
