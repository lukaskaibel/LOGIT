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
                    if workoutSet is DropSet {
                        // For dropsets, show each drop as a separate row
                        DropSetEntryRows(setNumber: index + 1, values: workoutSet.entryValues)
                    } else {
                        SetEntryRow(
                            setNumber: index + 1,
                            value: displayedValue(of: workoutSet)
                        )
                    }
                }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    // MARK: - Helper Methods

    /// The entry shown for a non-drop set: for compound sets the one belonging to the viewed
    /// exercise, otherwise the set's single entry.
    private func displayedValue(of workoutSet: WorkoutSet) -> SetEntryValues? {
        let values = workoutSet.entryValues
        if workoutSet is SuperSet {
            return values.first { $0.exercise != nil && $0.exercise == setGroup.exercise }
                ?? values.first
        }
        return values.first
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
/// field order the recorder uses: reps → weight, or weight → duration.
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
            if value.type.usesDuration {
                UnitView(
                    value: formatEntryDuration(value.duration),
                    unit: NSLocalizedString("min", comment: ""),
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
        ExerciseAttemptCell(setGroup: WorkoutSetGroup())
            .padding()
            .background(Color.background)
    }
}
