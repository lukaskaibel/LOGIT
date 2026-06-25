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
    var onTapExerciseName: ((Exercise) -> Void)? = nil
    /// When set, the primary name is held to this width and dissolves its trailing edge to
    /// transparent (instead of truncating with an ellipsis) if it's too long — used by the workout
    /// recorder so a long name fades out before the metric badge. The chevron is never faded. `nil`
    /// keeps the name at its natural width.
    var nameMaxWidth: CGFloat? = nil

    // MARK: - State

    @State private var isShowingExerciseDetailSheet = false
    @State private var isShowingSecondaryExerciseDetailSheet = false
    @State private var isNavigatingToExerciseDetail = false
    @State private var isNavigatingToSecondaryExerciseDetail = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let exercise = exercise {
                if let onTapExerciseName {
                    Button {
                        onTapExerciseName(exercise)
                    } label: {
                        exerciseLabel(exercise)
                    }
                } else if showDetailAsSheet {
                    Button {
                        isShowingExerciseDetailSheet = true
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
                        if let onTapExerciseName {
                            Button {
                                onTapExerciseName(secondaryExercise)
                            } label: {
                                secondaryExerciseLabel(secondaryExercise)
                            }
                        } else if showDetailAsSheet {
                            Button {
                                isShowingSecondaryExerciseDetailSheet = true
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
        .sheet(isPresented: $isShowingExerciseDetailSheet) {
            if let exercise = exercise {
                NavigationStack {
                    ExerciseDetailScreen(exercise: exercise, isShowingAsSheet: true)
                }
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isShowingSecondaryExerciseDetailSheet) {
            if let secondaryExercise = secondaryExercise {
                NavigationStack {
                    ExerciseDetailScreen(exercise: secondaryExercise, isShowingAsSheet: true)
                }
                .presentationDragIndicator(.visible)
            }
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
        primaryNameLabel(exercise.displayName)
            .frame(maxWidth: nameMaxWidth, alignment: .leading)
    }

    /// The exercise name and its navigation chevron. With `nameMaxWidth` set (the workout recorder),
    /// an over-long name dissolves to transparent instead of truncating with an ellipsis: `ViewThatFits`
    /// keeps the plain full name + tight chevron whenever it fits (so a short name is never masked),
    /// and otherwise masks only the name — leaving the chevron fully opaque — while negative spacing
    /// slides the chevron back over the masked, already-clear tail so it tucks against the fade as
    /// snugly as it does after a short name. Without `nameMaxWidth` it's the plain name + chevron,
    /// exactly as before, so every other caller is unchanged.
    @ViewBuilder
    private func primaryNameLabel(_ name: String) -> some View {
        if nameMaxWidth != nil {
            ViewThatFits(in: .horizontal) {
                withChevron(spacing: 3) {
                    Text(name)
                        .foregroundColor(.label)
                        .fixedSize(horizontal: true, vertical: false)
                }
                withChevron(spacing: -16) {
                    Text(name)
                        .foregroundColor(.label)
                        .mask(nameFadeMask)
                }
            }
        } else {
            withChevron(spacing: 3) {
                Text(name)
                    .foregroundColor(.label)
            }
        }
    }

    @ViewBuilder
    private func withChevron<Content: View>(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: spacing) {
            content()
            if navigationToDetailEnabled {
                NavigationChevron()
                    .foregroundColor(.secondaryLabel)
            }
        }
    }

    /// Trailing dissolve for an over-long name: opaque body, a ramp to clear, then a short clear tail.
    /// The chevron is slid back over that clear tail (see `primaryNameLabel`), which keeps it tucked
    /// against the fade and also hides any residual truncation "…" behind its opaque glyph.
    private var nameFadeMask: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.black)
            LinearGradient(
                gradient: Gradient(colors: [.black, .clear]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 20)
            Color.clear.frame(width: 16)
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
