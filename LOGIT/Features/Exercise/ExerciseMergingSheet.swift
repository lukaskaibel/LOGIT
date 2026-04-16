//
//  ExerciseMergingSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.04.26.
//

import CoreData
import SwiftUI

struct ExerciseMergingSheet: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var database: Database

    // MARK: - State

    @State private var selectedExercise: Exercise?
    @State private var searchText = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var isSourceAndTargetSwapped = false
    @State private var showMergeConfirmation = false
    @State private var mergeError: ExerciseMergeError?
    @State private var showErrorAlert = false

    // MARK: - Parameters

    let exercise: Exercise

    // MARK: - Computed

    private var source: Exercise {
        guard let selected = selectedExercise else { return exercise }
        if exercise.isDefaultExercise && !selected.isDefaultExercise {
            return selected
        }
        if selected.isDefaultExercise && !exercise.isDefaultExercise {
            return exercise
        }
        return isSourceAndTargetSwapped ? selected : exercise
    }

    private var target: Exercise {
        guard let selected = selectedExercise else { return exercise }
        if exercise.isDefaultExercise && !selected.isDefaultExercise {
            return exercise
        }
        if selected.isDefaultExercise && !exercise.isDefaultExercise {
            return selected
        }
        return isSourceAndTargetSwapped ? exercise : selected
    }

    private var directionIsLocked: Bool {
        guard let selected = selectedExercise else { return false }
        return exercise.isDefaultExercise != selected.isDefaultExercise
    }

    private var canMerge: Bool {
        guard let selected = selectedExercise else { return false }
        return !(exercise.isDefaultExercise && selected.isDefaultExercise)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if selectedExercise == nil {
                    selectionStep
                } else {
                    confirmationStep
                }
            }
            .navigationTitle(NSLocalizedString("mergeExercises", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(
                NSLocalizedString("error", comment: ""),
                isPresented: $showErrorAlert
            ) {
                Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
            } message: {
                if let mergeError {
                    Text(mergeError.errorDescription ?? "")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Step 1: Exercise Selection

    private var selectionStep: some View {
        FetchRequestWrapper(
            Exercise.self,
            sortDescriptors: [SortDescriptor(\.name)],
            predicate: ExercisePredicateFactory.getExercises(
                nameIncluding: "",
                withMuscleGroup: selectedMuscleGroup
            )
        ) { allExercises in
            let filtered = allExercises.filter { $0 != exercise }
            let exercises = FuzzySearchService.shared.searchExercises(searchText, in: filtered)
            let sortedExercises = searchText.isEmpty
                ? exercises.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
                : exercises

            VStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.placeholder)
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text(NSLocalizedString("searchExercises", comment: ""))
                    )
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .foregroundStyle(Color.placeholder)
                    }
                }
                .font(.title3)
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)

                MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)

                ScrollView {
                    LazyVStack(spacing: CELL_SPACING) {
                        ForEach(sortedExercises) { ex in
                            let isBothDefault = exercise.isDefaultExercise && ex.isDefaultExercise
                            Button {
                                if !isBothDefault {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedExercise = ex
                                    }
                                }
                            } label: {
                                HStack {
                                    ExerciseCell(exercise: ex)
                                    Spacer()
                                    if isBothDefault {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                    }
                                    NavigationChevron()
                                        .foregroundStyle(.secondary)
                                }
                                .padding(CELL_PADDING)
                                .tileStyle()
                                .contentShape(Rectangle())
                                .opacity(isBothDefault ? 0.5 : 1.0)
                            }
                            .buttonStyle(TileButtonStyle())
                            .disabled(isBothDefault)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                }
            }
        }
    }

    // MARK: - Step 2: Confirmation

    private var confirmationStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    Text(NSLocalizedString("mergeDirectionDescription", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    VStack(spacing: 20) {
                        exerciseCard(
                            exercise: source,
                            label: NSLocalizedString("willBeDeleted", comment: ""),
                            color: .red
                        )

                        HStack {
                            Image(systemName: "arrow.down")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if !directionIsLocked {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isSourceAndTargetSwapped.toggle()
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(Circle().fill(Color.accentColor))
                                }
                            }
                        }

                        exerciseCard(
                            exercise: target,
                            label: NSLocalizedString("willRemain", comment: ""),
                            color: .green
                        )
                    }
                    .padding(.horizontal)

                    if directionIsLocked {
                        Label(
                            NSLocalizedString("defaultExerciseAlwaysRemains", comment: ""),
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
            }

            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedExercise = nil
                        isSourceAndTargetSwapped = false
                    }
                } label: {
                    Text(NSLocalizedString("changeExercise", comment: ""))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Button(role: .destructive) {
                    showMergeConfirmation = true
                } label: {
                    Text(NSLocalizedString("mergeExercise", comment: ""))
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                .confirmationDialog(
                    Text(String(
                        format: NSLocalizedString("mergeConfirmation", comment: ""),
                        source.displayName,
                        target.displayName,
                        source.displayName
                    )),
                    isPresented: $showMergeConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(
                        NSLocalizedString("mergeExercise", comment: ""),
                        role: .destructive
                    ) {
                        performMerge()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Components

    private func exerciseCard(exercise: Exercise, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(color)

            VStack(spacing: 4) {
                Text(exercise.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let muscleGroup = exercise.muscleGroup {
                    Text(muscleGroup.description.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(muscleGroup.color.gradient)
                }
                if exercise.isDefaultExercise {
                    Text(NSLocalizedString("defaultExercise", comment: ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .tileStyle()
        }
    }

    // MARK: - Actions

    private func performMerge() {
        let mergeService = ExerciseMergeService(database: database)
        do {
            try mergeService.merge(source: source, into: target)
            dismiss()
        } catch let error as ExerciseMergeError {
            mergeError = error
            showErrorAlert = true
        } catch {}
    }
}
