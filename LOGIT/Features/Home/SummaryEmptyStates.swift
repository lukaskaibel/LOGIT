//
//  SummaryEmptyStates.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// MARK: - Pinned exercises empty state

/// Shown in the Summary's pinned-exercises section when nothing is pinned: two dimmed sample tiles
/// behind a "Pin your key lifts" call-to-action. The samples preview the real pinned-tile look —
/// which doubles as a Pro teaser, since the marquee metrics they show (Est. 1RM, volume) are exactly
/// what's gated. Replaces the old gray tip card.
struct PinnedExercisesEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                GhostExerciseTile(
                    name: "Bench Press",
                    value: "102",
                    unit: WeightUnit.used.rawValue,
                    color: MuscleGroup.chest.color,
                    points: [0.35, 0.5, 0.45, 0.7, 1.0]
                )
                GhostExerciseTile(
                    name: "Squat",
                    value: "145",
                    unit: WeightUnit.used.rawValue,
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

/// A dimmed sample of a pinned exercise tile — mirrors the `MetricTile` pinned look (name, Est. 1RM
/// caption, value, corner sparkline) closely enough to read as a believable preview.
private struct GhostExerciseTile: View {
    let name: String
    let value: String
    let unit: String
    let color: Color
    let points: [CGFloat]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(NSLocalizedString("estimatedOneRepMax", comment: ""))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 10)
            UnitView(value: value, unit: unit, configuration: .large, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
                .padding(.top, 2)
            Spacer(minLength: 8)
            GhostTrendLine(points: points, color: color)
                .frame(height: 24)
        }
        .padding(CELL_PADDING)
        .frame(height: 150, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
    }
}

/// A simple rounded-cap line through normalized 0…1 points — the sample sparkline on both empty states.
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
