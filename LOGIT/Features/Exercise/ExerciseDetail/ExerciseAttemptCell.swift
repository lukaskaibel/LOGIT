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
                    if let dropSet = workoutSet as? DropSet {
                        // For dropsets, show each drop as a separate row
                        DropSetEntryRows(setNumber: index + 1, dropSet: dropSet)
                    } else {
                        SetEntryRow(setNumber: index + 1, workoutSet: workoutSet, exercise: setGroup.exercise)
                    }
                }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    // MARK: - Helper Methods
    
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
    let workoutSet: WorkoutSet
    let exercise: Exercise?
    
    var body: some View {
        HStack(spacing: 0) {
            // Set number indicator
            Text("\(setNumber)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tertiaryLabel)
                .frame(width: 20)
            
            Spacer()
            
            // Reps and weight based on set type
            if let standardSet = workoutSet as? StandardSet {
                standardSetContent(standardSet)
            } else if let superSet = workoutSet as? SuperSet {
                superSetContent(superSet)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tertiaryBackground)
        )
    }
    
    // MARK: - Standard Set Content
    
    @ViewBuilder
    private func standardSetContent(_ standardSet: StandardSet) -> some View {
        HStack(spacing: 0) {
            UnitView(
                value: "\(standardSet.repetitions)",
                unit: NSLocalizedString("reps", comment: "").uppercased(),
                configuration: .small,
                unitColor: .secondaryLabel
            )
            .frame(width: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
            
            UnitView(
                value: formattedWeight(standardSet.weight),
                unit: WeightUnit.used.rawValue.uppercased(),
                configuration: .small,
                unitColor: .secondaryLabel
            )
            .frame(width: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
        }
    }
    
    // MARK: - Super Set Content
    
    @ViewBuilder
    private func superSetContent(_ superSet: SuperSet) -> some View {
        // Show the data for the exercise we're viewing
        let isFirstExercise = superSet.exercise == exercise
        let repetitions = isFirstExercise ? superSet.repetitionsFirstExercise : superSet.repetitionsSecondExercise
        let weight = isFirstExercise ? superSet.weightFirstExercise : superSet.weightSecondExercise
        
        HStack(spacing: 0) {
            UnitView(
                value: "\(repetitions)",
                unit: NSLocalizedString("reps", comment: "").uppercased(),
                configuration: .small,
                unitColor: .secondaryLabel
            )
            .frame(width: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
            
            UnitView(
                value: formattedWeight(weight),
                unit: WeightUnit.used.rawValue.uppercased(),
                configuration: .small,
                unitColor: .secondaryLabel
            )
            .frame(width: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
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

// MARK: - Drop Set Entry Rows

private struct DropSetEntryRows: View {
    let setNumber: Int
    let dropSet: DropSet
    
    var body: some View {
        let reps = dropSet.repetitions ?? []
        let weights = dropSet.weights ?? []
        
        VStack(spacing: 0) {
            ForEach(Array(zip(reps, weights).enumerated()), id: \.offset) { dropIndex, item in
                HStack(spacing: 0) {
                    // Set number indicator (only show on first drop)
                    Text(dropIndex == 0 ? "\(setNumber)" : "")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.tertiaryLabel)
                        .frame(width: 20)
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        UnitView(
                            value: "\(item.0)",
                            unit: NSLocalizedString("reps", comment: "").uppercased(),
                            configuration: .small,
                            unitColor: .secondaryLabel
                        )
                        .frame(width: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
                        
                        UnitView(
                            value: formattedWeight(item.1),
                            unit: WeightUnit.used.rawValue.uppercased(),
                            configuration: .small,
                            unitColor: .secondaryLabel
                        )
                        .frame(width: SET_GROUP_FIRST_COLUMN_WIDTH, alignment: .trailing)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tertiaryBackground)
        )
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
