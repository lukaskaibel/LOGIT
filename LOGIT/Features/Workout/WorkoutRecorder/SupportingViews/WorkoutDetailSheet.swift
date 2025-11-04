//
//  WorkoutDetailSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.03.25.
//

import SwiftUI

struct WorkoutDetailSheet: View {
    @Environment(\.dismiss) var dismiss

    @ObservedObject var workout: Workout
    let progress: Float

    var body: some View {
        VStack {
            HStack {
                Text((workout.name?.isEmpty ?? true) ? Workout.getStandardName(for: Date()) : workout.name!)
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundColor(Color.secondaryLabel)
                        .padding(8)
                        .background(Color.fill)
                        .clipShape(Circle())
                }
            }
            VStack {
                HStack {
                    Text(NSLocalizedString("progress", comment: ""))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.accentColor)
                }
                RoundedRectangle(cornerRadius: 5)
                    .foregroundStyle(Color.placeholder)
                    .frame(height: 20)
                    .overlay {
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 5)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: geometry.size.width * CGFloat(progress))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
            }
            .padding(CELL_PADDING)
            .tileStyle()
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("exercises", comment: ""))
                    Text("\(workout.exercises.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CELL_PADDING)
                .tileStyle()
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("sets", comment: ""))
                    Text("\(workout.sets.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CELL_PADDING)
                .tileStyle()
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("volume", comment: ""))
                    UnitView(
                        value: "\(formatWeightForDisplay(getVolume(of: workout.sets)))",
                        unit: WeightUnit.used.rawValue.uppercased()
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CELL_PADDING)
                .tileStyle()
            }
            Spacer()
        }
    }
}

private struct WorkoutDetailSheetPreviewWrapper: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        WorkoutDetailSheet(workout: database.testWorkout, progress: 0.3)
    }
}

#Preview {
    WorkoutDetailSheetPreviewWrapper()
        .previewEnvironmentObjects()
}
