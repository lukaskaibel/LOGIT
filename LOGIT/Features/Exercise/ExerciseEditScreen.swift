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
    /// The builder's selection. The measurement type is derived from it: the user composes
    /// "what do I type in per set" from four fields instead of decoding seven combined names.
    @State private var trackedFields: Set<SetTrackedField>
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

    /// Stable identity for the preview row's inert field indices.
    private static let previewSetID = UUID()

    // MARK: - Init

    init(
        exerciseToEdit: Exercise? = nil,
        onEditFinished: ((_ exercise: Exercise) -> Void)? = nil,
        initialExerciseName: String? = nil,
        initialMuscleGroup: MuscleGroup = .chest
    ) {
        self.exerciseToEdit = exerciseToEdit
        self.onEditFinished = onEditFinished
        let initialType = exerciseToEdit?.measurementType ?? .repsAndWeight
        _exerciseName = State(initialValue: initialExerciseName ?? exerciseToEdit?.displayName ?? "")
        _muscleGroup = State(initialValue: exerciseToEdit?.muscleGroup ?? initialMuscleGroup)
        _trackedFields = State(initialValue: initialType.trackedFields)
        _distanceStyle = State(
            initialValue: exerciseToEdit?.distanceStyle ?? initialType.distanceStyle ?? .long
        )
        _primaryMetric = State(initialValue: exerciseToEdit?.primaryMetric ?? .defaultMetric)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SECTION_SPACING) {
                    TextField(
                        NSLocalizedString("exerciseName", comment: ""),
                        text: $exerciseName
                    )
                    .focused($nameFieldIsFocused)
                    .font(.body.weight(.bold))
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding(.top, 30)

                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("selectMuscleGroup", comment: ""))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        MuscleGroupSelector(
                            selectedMuscleGroup: optionalMuscleGroupBinding,
                            canBeNil: false,
                            wraps: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("trackPerSet", comment: ""))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 8
                        ) {
                            ForEach(SetTrackedField.allCases, id: \.self) { field in
                                trackedFieldChip(for: field)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: muscleGroup)
                        if let hint = selectionHint {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }

                    if let measurementType {
                        setPreview(for: measurementType)

                        // Changing the type never rewrites history: recorded entries keep the
                        // fields they were performed with; only new sets record the new fields.
                        if exerciseToEdit != nil, measurementType != exerciseToEdit?.measurementType {
                            Text(NSLocalizedString("measurementTypeChangeInfo", comment: ""))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, -SECTION_SPACING + 10)
                        }

                        metricSection(for: measurementType)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .onChange(of: measurementType) { _, newType in
                guard let newType else { return }
                // A newly composed measurement resets the distance scale to its natural
                // default — the user can still flip it right in the preview.
                if let defaultStyle = newType.distanceStyle {
                    distanceStyle = defaultStyle
                }
                let allowed = ExercisePrimaryMetric.allowed(for: newType)
                if !allowed.contains(primaryMetric) {
                    primaryMetric = allowed.contains(.defaultMetric) ? .defaultMetric : allowed[0]
                }
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
                    .disabled(measurementType == nil)
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
            // Autofocus only for a brand-new exercise — when editing, the user usually came
            // for the measurement or muscle group, and the keyboard would bury both.
            if exerciseToEdit == nil {
                nameFieldIsFocused = true
            }
        }
    }

    // MARK: - Tracked Field Chips

    private func trackedFieldChip(for field: SetTrackedField) -> some View {
        let isSelected = trackedFields.contains(field)
        // A field stays addable only while some measurement type contains the grown selection —
        // this is where the two-field cap and the invalid pairings (reps+time) surface.
        let isEnabled = isSelected
            || SetMeasurementType.isSubsetOfAnyType(trackedFields.union([field]))
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.25)) {
                if isSelected {
                    trackedFields.remove(field)
                } else {
                    trackedFields.insert(field)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? selectionColor : Color.secondaryLabel)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: field))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(unitHint(for: field))
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(CELL_PADDING)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? selectionColor.secondaryTranslucentBackground
                    : Color.secondaryBackground
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? selectionColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.4)
        .accessibilityIdentifier("trackedFieldChip_\(field)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func title(for field: SetTrackedField) -> String {
        switch field {
        case .repetitions: return NSLocalizedString("repetitions", comment: "")
        case .weight: return NSLocalizedString("weight", comment: "")
        case .duration: return NSLocalizedString("measurementType.duration", comment: "")
        case .distance: return NSLocalizedString("measurementType.distance", comment: "")
        }
    }

    /// The unit the recorder's field will carry — the caption explains a chip in the same
    /// vocabulary the set row will use. Reps use the human-readable short form ("Reps"),
    /// not the field's terse "rps".
    private func unitHint(for field: SetTrackedField) -> String {
        switch field {
        case .repetitions: return NSLocalizedString("repsShort", comment: "")
        case .weight: return WeightUnit.used.rawValue
        case .duration: return NSLocalizedString("sec", comment: "")
        case .distance: return "\(DistanceUnit.used.shortUnit) / \(DistanceUnit.used.rawValue)"
        }
    }

    /// Only two incomplete selections are reachable (adding is capped to subsets of real
    /// types): nothing at all, or weight without a partner.
    private var selectionHint: String? {
        guard measurementType == nil else { return nil }
        return trackedFields.isEmpty
            ? NSLocalizedString("trackingEmptyHint", comment: "")
            : NSLocalizedString("trackingWeightAloneHint", comment: "")
    }

    // MARK: - Set Preview

    /// A live render of one set row exactly as the recorder will show it — real field
    /// components in their read-only mode, recessed on the same tile the set cells sit on.
    private func setPreview(for measurementType: SetMeasurementType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("setPreviewCaption", comment: ""))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                Text("1")
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                Spacer()
                previewFields(for: measurementType)
            }
            .padding(.horizontal, CELL_PADDING)
            .padding(.vertical, 10)
            .secondaryTileStyle(insetShadow: true)
            .canEdit(false)
            if measurementType.usesDistance {
                HStack {
                    Text(NSLocalizedString("distanceUnit", comment: ""))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(
                        NSLocalizedString("distanceUnit", comment: ""),
                        selection: $distanceStyle
                    ) {
                        ForEach(SetMeasurementType.DistanceStyle.allCases, id: \.self) { style in
                            Text(unitLabel(for: style)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 140)
                    .accessibilityIdentifier("distanceStylePicker")
                }
                .font(.callout)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
        .accessibilityIdentifier("setPreviewTile")
    }

    /// Mirrors `SetEntryFieldsRow.fields`' order for each type, with sample values in the
    /// read-only rendering the workout detail uses.
    @ViewBuilder
    private func previewFields(for measurementType: SetMeasurementType) -> some View {
        switch measurementType {
        case .repsAndWeight:
            previewRepetitionsField(tertiary: 0)
            previewWeightField(tertiary: 1)
        case .repsOnly:
            previewRepetitionsField(tertiary: 0)
        case .duration:
            previewDurationField(tertiary: 0)
        case .weightAndDuration:
            previewWeightField(tertiary: 0)
            previewDurationField(tertiary: 1)
        case .distance:
            previewDistanceField(tertiary: 0)
        case .distanceAndDuration:
            previewDistanceField(tertiary: 0)
            previewDurationField(tertiary: 1)
        case .weightAndDistance:
            previewWeightField(tertiary: 0)
            previewDistanceField(tertiary: 1)
        }
    }

    private func previewIndex(_ tertiary: Int) -> IntegerField.Index {
        IntegerField.Index(setID: Self.previewSetID, secondary: 0, tertiary: tertiary)
    }

    private func previewRepetitionsField(tertiary: Int) -> some View {
        IntegerField(
            placeholder: 0,
            value: .constant(12),
            maxDigits: 4,
            index: previewIndex(tertiary),
            focusedIntegerFieldIndex: .constant(nil),
            unit: NSLocalizedString("reps", comment: "")
        )
    }

    private func previewWeightField(tertiary: Int) -> some View {
        DecimalField(
            placeholder: 0,
            value: .constant(WeightUnit.used == .kg ? 60 : 135),
            maxDigits: 4,
            decimalPlaces: WeightUnit.used == .kg ? 3 : 2,
            index: previewIndex(tertiary),
            focusedIntegerFieldIndex: .constant(nil),
            unit: WeightUnit.used.rawValue
        )
    }

    private func previewDurationField(tertiary: Int) -> some View {
        IntegerField(
            placeholder: 0,
            value: .constant(45),
            maxDigits: 4,
            index: previewIndex(tertiary),
            focusedIntegerFieldIndex: .constant(nil),
            unit: NSLocalizedString("sec", comment: "")
        )
    }

    @ViewBuilder
    private func previewDistanceField(tertiary: Int) -> some View {
        switch distanceStyle {
        case .long:
            DecimalField(
                placeholder: 0,
                value: .constant(5),
                maxDigits: 4,
                decimalPlaces: 2,
                index: previewIndex(tertiary),
                focusedIntegerFieldIndex: .constant(nil),
                unit: DistanceUnit.used.rawValue
            )
        case .short:
            IntegerField(
                placeholder: 0,
                value: .constant(40),
                maxDigits: 5,
                index: previewIndex(tertiary),
                focusedIntegerFieldIndex: .constant(nil),
                unit: DistanceUnit.used.shortUnit
            )
        }
    }

    /// Compact segment label — "km" / "m" (or "mi" / "yd"), matching the preview's own unit.
    private func unitLabel(for style: SetMeasurementType.DistanceStyle) -> String {
        switch style {
        case .long: return DistanceUnit.used.rawValue
        case .short: return DistanceUnit.used.shortUnit
        }
    }

    // MARK: - Progress Metric

    private func metricSection(for measurementType: SetMeasurementType) -> some View {
        // Only metrics that fit the chosen measurement — a plank never offers e1RM.
        let allowedMetrics = ExercisePrimaryMetric.allowed(for: measurementType)
        return VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("progressMetric", comment: ""))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(NSLocalizedString("progressMetricCaption", comment: ""))
                .font(.footnote)
                .foregroundStyle(.tertiary)
            VStack(spacing: 0) {
                ForEach(allowedMetrics, id: \.self) { metric in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        primaryMetric = metric
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: primaryMetric == metric ? "circle.inset.filled" : "circle")
                                .font(.title3)
                                .foregroundStyle(
                                    primaryMetric == metric ? selectionColor : Color.secondaryLabel
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(metric.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.label)
                                Text(metric.caption)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondaryLabel)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(CELL_PADDING)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progressMetricOption_\(metric.rawValue)")
                    .accessibilityAddTraits(primaryMetric == metric ? .isSelected : [])
                    if metric != allowedMetrics.last {
                        Divider()
                            .padding(.leading, CELL_PADDING + 32)
                    }
                }
            }
            .tileStyle()
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.2), value: muscleGroup)
        }
    }

    // MARK: - Computed Properties

    /// Selection controls wear the chosen muscle group's color, so the whole sheet reads as
    /// one exercise rather than the muscle capsules disagreeing with a lime accent below.
    private var selectionColor: Color {
        muscleGroup.color
    }

    private var measurementType: SetMeasurementType? {
        SetMeasurementType(trackedFields: trackedFields)
    }

    private func saveExercise() {
        guard let measurementType else { return }
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
