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
    @State private var measurementType: SetMeasurementType
    @State private var distanceStyle: SetMeasurementType.DistanceStyle
    @State private var primaryMetric: ExercisePrimaryMetric
    @State private var showingExerciseExistsAlert: Bool = false
    @State private var showingExerciseNameEmptyAlert: Bool = false
    @State private var showingInvalidNameAlert: Bool = false
    @State private var invalidNameMessage: String = ""
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
        _exerciseName = State(initialValue: initialExerciseName ?? exerciseToEdit?.displayName ?? "")
        _muscleGroup = State(initialValue: exerciseToEdit?.muscleGroup ?? initialMuscleGroup)
        _measurementType = State(initialValue: exerciseToEdit?.measurementType ?? .repsAndWeight)
        _distanceStyle = State(
            initialValue: exerciseToEdit?.distanceStyle
                ?? (exerciseToEdit?.measurementType ?? .repsAndWeight).distanceStyle
                ?? .long
        )
        _primaryMetric = State(initialValue: exerciseToEdit?.primaryMetric ?? .defaultMetric)
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

                VStack(alignment: .leading) {
                    Text(NSLocalizedString("measurementType", comment: ""))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    Picker(NSLocalizedString("measurementType", comment: ""), selection: $measurementType) {
                        ForEach(SetMeasurementType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    // Changing the type never rewrites history: recorded entries keep the
                    // fields they were performed with; only new sets record the new fields.
                    if exerciseToEdit != nil, measurementType != exerciseToEdit?.measurementType {
                        Text(NSLocalizedString("measurementTypeChangeInfo", comment: ""))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }

                // Distance scale (km vs m, mi vs yd) — a display choice; distances are always
                // stored in meters, so switching never touches recorded values.
                if measurementType.usesDistance {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("distanceUnit", comment: ""))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Picker(NSLocalizedString("distanceUnit", comment: ""), selection: $distanceStyle) {
                            ForEach(SetMeasurementType.DistanceStyle.allCases, id: \.self) { style in
                                Text(distanceStyleTitle(for: style)).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .onChange(of: measurementType) { _, newType in
                            // A newly chosen measurement resets the scale to its natural
                            // default — the user can still flip it right here.
                            if let defaultStyle = newType.distanceStyle {
                                distanceStyle = defaultStyle
                            }
                        }
                    }
                }

                VStack(alignment: .leading) {
                    Text(NSLocalizedString("progressMetric", comment: ""))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    // Only metrics that fit the chosen measurement — a plank never offers e1RM.
                    let allowedMetrics = ExercisePrimaryMetric.allowed(for: measurementType)
                    Picker(NSLocalizedString("progressMetric", comment: ""), selection: $primaryMetric) {
                        ForEach(allowedMetrics, id: \.self) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: measurementType) { _, newType in
                        let allowed = ExercisePrimaryMetric.allowed(for: newType)
                        if !allowed.contains(primaryMetric) {
                            primaryMetric = allowed.contains(.defaultMetric) ? .defaultMetric : allowed[0]
                        }
                    }
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
                        let trimmedName = exerciseName.trimmingCharacters(in: .whitespaces)
                        
                        if trimmedName.isEmpty {
                            showingExerciseNameEmptyAlert = true
                        } else if trimmedName.hasPrefix("_default") {
                            invalidNameMessage = NSLocalizedString("exerciseNameCantStartWithDefault", comment: "")
                            showingInvalidNameAlert = true
                        } else if exerciseToEdit == nil {
                            // Check if name matches any existing exercise's name (internal) or displayName (computed/localized)
                            let allExercises = database.getExercises()
                            let nameExists = allExercises.contains { exercise in
                                exercise.displayName.lowercased() == trimmedName.lowercased()
                            }
                            if nameExists {
                                showingExerciseExistsAlert = true
                            } else {
                                saveExercise()
                            }
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
            .alert(
                invalidNameMessage,
                isPresented: $showingInvalidNameAlert
            ) {
                Button(NSLocalizedString("ok", comment: "")) {
                    showingInvalidNameAlert = false
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
            exerciseToEdit.measurementType = measurementType
            exercise = exerciseToEdit
        } else {
            exercise = database.newExercise(
                name: exerciseName.trimmingCharacters(in: .whitespacesAndNewlines),
                muscleGroup: muscleGroup,
                measurementType: measurementType
            )
        }
        if measurementType.usesDistance {
            exercise.distanceStyle = distanceStyle
        }
        database.save()
        exercise.primaryMetric = primaryMetric
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
