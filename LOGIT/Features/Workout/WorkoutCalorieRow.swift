//
//  WorkoutCalorieRow.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.07.26.
//

import SwiftUI

/// The slim estimated-calories row on the workout detail screen.
///
/// Deliberately quieter than the measured stat tiles above it — one settings-row-height
/// line, secondary label, tilde value — because the number is derived, not measured, and
/// calories are not a primary feature. Tapping it opens `CalorieEstimateSheet`, which
/// decomposes the number into exactly the inputs the estimator used.
struct WorkoutCalorieRow: View {
    @ObservedObject var workout: Workout
    let estimate: CalorieEstimator.Estimate?
    /// True when the only thing missing for an estimate is a logged body weight — the row
    /// then explains that instead of showing a number. All other nil reasons hide the row.
    let isMissingBodyWeight: Bool

    @State private var isShowingEstimateSheet = false
    @State private var isShowingBodyWeightScreen = false

    var body: some View {
        if let estimate {
            Button {
                isShowingEstimateSheet = true
            } label: {
                row {
                    Text("~\(estimate.activeKilocalories)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.label)
                        + Text(" kcal")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.secondaryLabel)
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryLabel)
                }
            }
            .sheet(isPresented: $isShowingEstimateSheet) {
                CalorieEstimateSheet(workout: workout, estimate: estimate)
            }
        } else if isMissingBodyWeight {
            Button {
                isShowingBodyWeightScreen = true
            } label: {
                row(dimmed: true) {
                    Text(NSLocalizedString("add", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    NavigationChevron()
                }
            }
            .sheet(isPresented: $isShowingBodyWeightScreen) {
                NavigationStack {
                    MeasurementDetailScreen(measurementType: .bodyweight)
                }
            }
        }
    }

    /// The shared single-line frame: flame, label, then the trailing content. The flame wears
    /// the workout's muscle-group gradient — the same identity treatment as the stat tiles'
    /// run bars and the detail header's donut.
    private func row(dimmed: Bool = false, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.footnote)
                .foregroundStyle(
                    dimmed
                        ? AnyShapeStyle(Color.secondaryLabel)
                        : workout.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing)
                )
            Text(NSLocalizedString(dimmed ? "logBodyWeightToEstimate" : "estCalories", comment: ""))
                .font(.subheadline)
                .foregroundStyle(dimmed ? Color.secondaryLabel : Color.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, CELL_PADDING)
        .padding(.vertical, 11)
        .tileStyle()
        .contentShape(Rectangle())
    }
}

// MARK: - Estimate Sheet

/// Decomposes the calorie estimate into the inputs it was computed from — every line
/// traceable to something the user logged. This transparency is the feature: an estimate
/// whose inputs are inspectable doesn't read as random.
struct CalorieEstimateSheet: View {
    @ObservedObject var workout: Workout
    let estimate: CalorieEstimator.Estimate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(NSLocalizedString("estimatedCalories", comment: ""))
                    .font(.title2.weight(.bold))
                Text("\(workout.name ?? "") · \(workout.date?.description(.medium) ?? "")")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryLabel)
                    .padding(.bottom, 16)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("~\(estimate.activeKilocalories)")
                        .font(.system(size: 38, weight: .bold))
                    Text("kcal")
                        .font(.headline)
                        .foregroundStyle(Color.secondaryLabel)
                }

                splitBar
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                inputRow(
                    NSLocalizedString("duration", comment: ""),
                    value: formattedWorkoutDuration(minutes: estimate.billableSeconds / 60)
                )
                inputRow(
                    NSLocalizedString("workingTime", comment: ""),
                    value: "~\(formattedWorkoutDuration(minutes: max(1, estimate.workingSeconds / 60)))",
                    detail: NSLocalizedString("fromYourLoggedSets", comment: "")
                )
                inputRow(
                    NSLocalizedString("bodyweight", comment: ""),
                    value: "\(convertWeightForDisplaying(Int64(estimate.bodyWeightKilograms * 1000))) \(WeightUnit.used.rawValue)",
                    detail: estimate.bodyWeightDate.map {
                        String(
                            format: NSLocalizedString("loggedDateFormat", comment: ""),
                            $0.description(.medium)
                        )
                    }
                )
                inputRow(
                    NSLocalizedString("sessionIntensity", comment: ""),
                    value: String(format: "%.1f METs", estimate.sessionMET),
                    detail: NSLocalizedString("publishedStrengthRange", comment: ""),
                    showsDivider: false
                )

                Text(NSLocalizedString("calorieEstimateExplanation", comment: ""))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryLabel)
                    .padding(.top, 16)
                Text(NSLocalizedString("calorieEstimateHealthNote", comment: ""))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryLabel)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .padding(.top, 8)
        }
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
    }

    /// Working vs. rest share of the billed duration — drawn honestly from the same numbers
    /// the formula used.
    private var splitBar: some View {
        let workingShare = min(
            Double(estimate.workingSeconds) / Double(max(estimate.billableSeconds, 1)), 1
        )
        let restMinutes = max(0, estimate.billableSeconds - estimate.workingSeconds) / 60
        return VStack(spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    Capsule()
                        .fill(workout.sets.muscleGroupGradient(startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * workingShare))
                    Capsule()
                        .fill(Color.fill)
                }
            }
            .frame(height: 8)
            HStack {
                legendText(
                    minutes: max(1, estimate.workingSeconds / 60),
                    label: NSLocalizedString("workingShareLabel", comment: "")
                )
                Spacer()
                legendText(
                    minutes: restMinutes,
                    label: NSLocalizedString("restShareLabel", comment: "")
                )
            }
        }
    }

    private func legendText(minutes: Int, label: String) -> Text {
        Text(formattedWorkoutDuration(minutes: minutes))
            .font(.caption.weight(.semibold))
            .foregroundColor(Color.label)
            + Text(" \(label)")
            .font(.caption)
            .foregroundColor(Color.secondaryLabel)
    }

    private func inputRow(
        _ title: String, value: String, detail: String? = nil, showsDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryLabel)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
            if showsDivider {
                Divider()
            }
        }
    }
}
