//
//  ExerciseHeader.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 27.11.22.
//

import SwiftUI

struct ExerciseHeader: View {

    // MARK: - Parameters

    let exercise: Exercise?
    let secondaryExercise: Exercise?
    let noExerciseAction: () -> Void
    let noSecondaryExerciseAction: (() -> Void)?
    let isSuperSet: Bool
    let navigationToDetailEnabled: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let exercise = exercise {
                NavigationLink(destination: ExerciseDetailScreen(exercise: exercise)) {
                    HStack(spacing: 3) {
                        Text(exercise.name ?? NSLocalizedString("noName", comment: ""))
                            .foregroundColor(.label)
                        if navigationToDetailEnabled {
                            NavigationChevron()
                                .foregroundColor(.secondaryLabel)
                        }
                    }
                }
            } else {
                Button(action: noExerciseAction) {
                    HStack(spacing: 3) {
                        Text(NSLocalizedString("selectExercise", comment: ""))
                        if navigationToDetailEnabled {
                            NavigationChevron()
                                .foregroundColor(.secondaryLabel)
                        }
                    }
                }
                .foregroundColor(.placeholder)
            }
            if isSuperSet {
                HStack {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.body.weight(.medium))
                        .padding(.leading)
                    if let secondaryExercise = secondaryExercise {
                        NavigationLink(
                            destination: ExerciseDetailScreen(exercise: secondaryExercise)
                        ) {
                            HStack(spacing: 3) {
                                Text(
                                    secondaryExercise.name
                                        ?? NSLocalizedString("noName", comment: "")
                                )
                                if navigationToDetailEnabled {
                                    NavigationChevron()
                                        .foregroundColor(.secondaryLabel)
                                }
                            }
                        }
                    } else if let noSecondaryExerciseAction = noSecondaryExerciseAction {
                        Button(action: noSecondaryExerciseAction) {
                            HStack(spacing: 3) {
                                Text(NSLocalizedString("selectExercise", comment: ""))
                                if navigationToDetailEnabled {
                                    NavigationChevron()
                                        .foregroundColor(.secondaryLabel)
                                }
                            }
                        }
                        .foregroundColor(.placeholder)
                    }
                    Spacer()
                }
            }
        }
        .textCase(nil)
        .font(.title3.weight(.bold))
        .foregroundColor(.label)
        .lineLimit(1)
    }
}
