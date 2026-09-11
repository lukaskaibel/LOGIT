//
//  ExerciseAttemptCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 19.01.26.
//

import SwiftUI

struct ExerciseAttemptCell: View {
    
    // MARK: - Parameters
    
    let setGroup: WorkoutSetGroup
    /// The exercise whose history this cell is a row of. A super set's set holds an entry for
    /// each of its two exercises, and only this one's is this cell's to show — see
    /// `displayedValues(of:)`.
    let exercise: Exercise
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with date and workout name
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let date = setGroup.workout?.date {
                        Text(formattedDate(date))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.label)
                    }
                    if let workoutName = setGroup.workout?.name, !workoutName.isEmpty {
                        Text(workoutName)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
                Spacer()
                Text("\(setGroup.numberOfSets) \(setGroup.numberOfSets == 1 ? NSLocalizedString("set", comment: "") : NSLocalizedString("sets", comment: ""))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.tertiaryLabel)
            }
            
            // Set entries
            VStack(spacing: CELL_SPACING) {
                ForEach(Array(setGroup.sets.enumerated()), id: \.element.id) { index, workoutSet in
                    let values = displayedValues(of: workoutSet)
                    if workoutSet is DropSet {
                        // For dropsets, show each drop as a separate row
                        DropSetEntryRows(setNumber: index + 1, values: values)
                    } else {
                        SetEntryRow(setNumber: index + 1, value: values.first)
                    }
                }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    // MARK: - Helper Methods

    /// What this set contributed to the exercise being viewed: its own entries. A super set
    /// pairs two exercises in one set, so this is the difference between an exercise's history
    /// showing its own reps and weights and showing its partner's — matching the set GROUP's
    /// primary exercise instead is how the second exercise of every superset came to report the
    /// first one's numbers. A drop set returns all of its drops, a standard set its one entry.
    private func displayedValues(of workoutSet: WorkoutSet) -> [SetEntryValues] {
        let values = workoutSet.entryValues(for: exercise)
        // Sets old enough to name no exercise at all can't be attributed — show them rather
        // than leaving the row blank.
        return values.isEmpty ? workoutSet.entryValues.filter { $0.exercise == nil } : values
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        
        if date < oneYearAgo {
            // More than a year ago: include the year
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        } else {
            // Within the last year: no year needed
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }
}

// MARK: - Set Entry Row

private struct SetEntryRow: View {
    let setNumber: Int
    let value: SetEntryValues?

    var body: some View {
        HStack(spacing: 0) {
            // Set number indicator
            Text("\(setNumber)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tertiaryLabel)
                .frame(width: 30, alignment: .leading)

            Spacer()

            if let value {
                EntryValueColumns(value: value)
            }
        }
        .padding(.vertical, CELL_PADDING)
        .padding(.horizontal, CELL_PADDING)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                .foregroundStyle(Color.tertiaryBackground)
        )
        .cornerRadius(15)
    }
}

// MARK: - Drop Set Entry Rows

private struct DropSetEntryRows: View {
    let setNumber: Int
    let values: [SetEntryValues]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { dropIndex, value in
                HStack(spacing: 0) {
                    // Set number indicator (only show on first drop)
                    Text(dropIndex == 0 ? "\(setNumber)" : "")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.tertiaryLabel)
                        .frame(width: 30, alignment: .leading)

                    Spacer()

                    EntryValueColumns(value: value)
                }
                .padding(.vertical, CELL_PADDING)
                .padding(.horizontal, CELL_PADDING)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                .foregroundStyle(Color.tertiaryBackground)
        )
        .cornerRadius(15)
    }
}

// MARK: - Entry Value Columns

/// One entry's recorded values as unit columns, laid out by measurement type in the same
/// field order the recorder uses: reps → weight, weight → distance, or distance → duration.
private struct EntryValueColumns: View {
    let value: SetEntryValues

    var body: some View {
        HStack(spacing: 0) {
            if value.type.usesRepetitions {
                UnitView(
                    value: "\(value.repetitions)",
                    unit: NSLocalizedString("reps", comment: ""),
                    configuration: .normal,
                    unitColor: .secondaryLabel
                )
                .frame(minWidth: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
            }
            if value.type.usesWeight {
                UnitView(
                    value: formattedWeight(value.weight),
                    unit: WeightUnit.used.rawValue,
                    configuration: .normal,
                    unitColor: .secondaryLabel
                )
                .frame(minWidth: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
            }
            if let distanceStyle = value.type.distanceStyle(for: value.exercise) {
                UnitView(
                    value: formatDistanceForDisplay(value.distanceMm, style: distanceStyle),
                    unit: distanceUnitTitle(for: distanceStyle),
                    configuration: .normal,
                    unitColor: .secondaryLabel
                )
                .frame(minWidth: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
            }
            if value.type.usesDuration {
                UnitView(
                    value: formatDurationForDisplay(milliseconds: value.durationMs),
                    unit: "",
                    configuration: .normal,
                    unitColor: .secondaryLabel
                )
                .frame(minWidth: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
            }
        }
    }

    private func formattedWeight(_ weight: Int64) -> String {
        let displayWeight = convertWeightForDisplayingDecimal(weight)
        if displayWeight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", displayWeight)
        } else {
            return String(format: "%.1f", displayWeight)
        }
    }
}

// MARK: - Preview

struct ExerciseAttemptCell_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseAttemptCell(setGroup: WorkoutSetGroup(), exercise: Exercise())
            .padding()
            .background(Color.background)
    }
}
