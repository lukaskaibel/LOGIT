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
    var showDetailAsSheet: Bool = false

    // MARK: - State

    @State private var exerciseDetailSheetExercise: Exercise?
    @State private var secondaryExerciseDetailSheetExercise: Exercise?
    @State private var isNavigatingToExerciseDetail = false
    @State private var isNavigatingToSecondaryExerciseDetail = false
    @State private var pendingMergeTarget: Exercise?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let exercise = exercise {
                if showDetailAsSheet {
                    Button {
                        exerciseDetailSheetExercise = exercise
                    } label: {
                        exerciseLabel(exercise)
                    }
                } else {
                    Button {
                        isNavigatingToExerciseDetail = true
                    } label: {
                        exerciseLabel(exercise)
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
                        if showDetailAsSheet {
                            Button {
                                secondaryExerciseDetailSheetExercise = secondaryExercise
                            } label: {
                                secondaryExerciseLabel(secondaryExercise)
                            }
                        } else {
                            Button {
                                isNavigatingToSecondaryExerciseDetail = true
                            } label: {
                                secondaryExerciseLabel(secondaryExercise)
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
        .font(.body.weight(.semibold))
        .foregroundColor(.label)
        .lineLimit(1)
        .sheet(item: $exerciseDetailSheetExercise, onDismiss: {
            if let target = pendingMergeTarget {
                pendingMergeTarget = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    exerciseDetailSheetExercise = target
                }
            }
        }) { sheetExercise in
            NavigationStack {
                ExerciseDetailScreen(
                    exercise: sheetExercise,
                    isShowingAsSheet: true,
                    onNavigateToExercise: { targetExercise in
                        pendingMergeTarget = targetExercise
                    }
                )
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $secondaryExerciseDetailSheetExercise, onDismiss: {
            if let target = pendingMergeTarget {
                pendingMergeTarget = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    exerciseDetailSheetExercise = target
                }
            }
        }) { sheetExercise in
            NavigationStack {
                ExerciseDetailScreen(
                    exercise: sheetExercise,
                    isShowingAsSheet: true,
                    onNavigateToExercise: { targetExercise in
                        pendingMergeTarget = targetExercise
                    }
                )
            }
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $isNavigatingToExerciseDetail) {
            if let exercise = exercise {
                ExerciseDetailScreen(exercise: exercise)
            }
        }
        .navigationDestination(isPresented: $isNavigatingToSecondaryExerciseDetail) {
            if let secondaryExercise = secondaryExercise {
                ExerciseDetailScreen(exercise: secondaryExercise)
            }
        }
    }

    // MARK: - Helper Views

    private func exerciseLabel(_ exercise: Exercise) -> some View {
        HStack(spacing: 3) {
            Text(exercise.displayName)
                .foregroundColor(.label)
            if navigationToDetailEnabled {
                NavigationChevron()
                    .foregroundColor(.secondaryLabel)
            }
        }
    }

    private func secondaryExerciseLabel(_ exercise: Exercise) -> some View {
        HStack(spacing: 3) {
            Text(exercise.displayName)
            if navigationToDetailEnabled {
                NavigationChevron()
                    .foregroundColor(.secondaryLabel)
            }
        }
    }
}
