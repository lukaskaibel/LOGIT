//
//  PersonalBestRow.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// MARK: - Shared record row

/// One record on its own secondary tile — the muscle-tinted trophy badge, the exercise + metric, and
/// the new best in its muscle-group gradient. Shared by the workout-detail records tile and the
/// Summary records tile so the rows render identically; lives in SharedUI so both surfaces use the
/// one component.
struct PersonalBestRow: View {
    let record: WorkoutProgressReport.PRRecord

    var body: some View {
        let color = record.exercise.muscleGroup?.color ?? .accentColor
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(color.gradient)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.exercise.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text(record.metric.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            personalRecordValueView(for: record, configuration: .normal)
                .foregroundStyle(color.gradient)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .secondaryTileStyle(insetShadow: true)
    }
}

// MARK: - Record value rendering

/// A record's base value as a display string and its unit, in the metric's units. The tile and the
/// card both render it through `UnitView`, which uppercases the unit, so the casing can't drift.
func personalRecordDisplay(_ base: Int, metric: ExercisePrimaryMetric) -> (value: String, unit: String) {
    switch metric {
    case .estimatedOneRepMax: return (formatEstimatedOneRepMax(base), WeightUnit.used.rawValue)
    case .weight: return (formatWeightForDisplay(base), WeightUnit.used.rawValue)
    case .repetitions: return (String(base), NSLocalizedString("reps", comment: ""))
    case .duration: return (String(base), NSLocalizedString("sec", comment: ""))
    }
}

/// A record's value as `UnitView` — the caller tints it in the exercise's muscle-group gradient.
private func personalRecordValueView(
    for record: WorkoutProgressReport.PRRecord,
    configuration: UnitViewConfiguration = .normal
) -> some View {
    let display = personalRecordDisplay(record.value, metric: record.metric)
    return UnitView(value: display.value, unit: display.unit, configuration: configuration)
}
