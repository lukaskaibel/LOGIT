//
//  ExerciseEditScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 18.03.22.
//

import SwiftUI

struct ExerciseEditScreen: View {

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var database: Database

    // MARK: - State

    @State private var exerciseName: String
    @State private var muscleGroup: MuscleGroup
    @State private var showingExerciseExistsAlert: Bool = false
    @State private var showingExerciseNameEmptyAlert: Bool = false
    @FocusState private var nameFieldIsFocused: Bool

    // MARK: - Variables

    private let exerciseToEdit: Exercise?
    private let onEditFinished: ((_ exercise: Exercise) -> Void)?

    // MARK: - Init

    init(
        exerciseToEdit: Exercise? = nil,
        onEditFinished: ((_ exercise: Exercise) -> Void)? = nil,
        initialExerciseName: String? = nil,
        initialMuscleGroup: MuscleGroup = .chest
    ) {
        self.exerciseToEdit = exerciseToEdit
        self.onEditFinished = onEditFinished
        _exerciseName = State(initialValue: initialExerciseName ?? exerciseToEdit?.name ?? "")
        _muscleGroup = State(initialValue: exerciseToEdit?.muscleGroup ?? initialMuscleGroup)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: SECTION_SPACING) {
                TextField(
                    NSLocalizedString("exerciseName", comment: ""),
                    text: $exerciseName
                )
                .focused($nameFieldIsFocused)
                .font(.body.weight(.bold))
                .padding(CELL_PADDING)
                .tileStyle()
                .padding(.horizontal)
                .padding(.top, 30)

                VStack(alignment: .leading) {
                    Text(NSLocalizedString("selectMuscleGroup", comment: ""))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    MuscleGroupSelector(
                        selectedMuscleGroup: optionalMuscleGroupBinding,
                        canBeNil: false
                    )
                }
                Spacer()
            }
            .navigationTitle(
                exerciseToEdit != nil
                    ? "\(NSLocalizedString("edit", comment: "")) \(NSLocalizedString("exercise", comment: ""))"
                    : NSLocalizedString("newExercise", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("save", comment: "")) {
                        if exerciseName.trimmingCharacters(in: .whitespaces).isEmpty {
                            showingExerciseNameEmptyAlert = true
                        } else if exerciseToEdit == nil
                                    && !database.getExercises().filter({ $0.name?.lowercased() == exerciseName.lowercased() }).isEmpty
                        {
                            showingExerciseExistsAlert = true
                        } else {
                            saveExercise()
                        }
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .alert(
                "\(exerciseName.trimmingCharacters(in: .whitespaces)) \(NSLocalizedString("alreadyExists", comment: ""))",
                isPresented: $showingExerciseExistsAlert
            ) {
                Button(NSLocalizedString("ok", comment: "")) {
                    showingExerciseExistsAlert = false
                }
            }
            .alert(
                NSLocalizedString("nameCantBeEmpty", comment: ""),
                isPresented: $showingExerciseNameEmptyAlert
            ) {
                Button(NSLocalizedString("ok", comment: "")) {
                    showingExerciseNameEmptyAlert = false
                }
            }
        }
        .onAppear {
            nameFieldIsFocused = true
        }
    }

    // MARK: - Computed Properties

    private func saveExercise() {
        let exercise: Exercise
        if let exerciseToEdit = exerciseToEdit {
            exerciseToEdit.name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
            exerciseToEdit.muscleGroup = muscleGroup
            exercise = exerciseToEdit
        } else {
            exercise = database.newExercise(
                name: exerciseName.trimmingCharacters(in: .whitespacesAndNewlines),
                muscleGroup: muscleGroup
            )
        }
        database.save()
        dismiss()
        onEditFinished?(exercise)
    }

    private var optionalMuscleGroupBinding: Binding<MuscleGroup?> {
        Binding(
            get: { muscleGroup },
            set: { muscleGroup = $0 ?? muscleGroup }
        )
    }

}

struct EditExerciseView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseEditScreen(initialMuscleGroup: .chest)
            .previewEnvironmentObjects()
    }
}
