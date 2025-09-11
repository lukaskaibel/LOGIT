//
//  WorkoutDetailScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 20.12.21.
//

import CoreData
import SwiftUI

struct WorkoutDetailScreen: View {
    enum SheetType: Int, Identifiable {
        case newTemplateFromWorkout, templateDetail, workoutEditor
        var id: Int { rawValue }
    }

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - State

    @State private var isShowingDeleteWorkoutAlert: Bool = false
    @State private var sheetType: SheetType? = nil
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var isMuscleGroupExpanded: Bool = false

    // MARK: - Variables

    @StateObject var workout: Workout
    let canNavigateToTemplate: Bool

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                workoutHeader

                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("overview", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: CELL_SPACING) {
                        workoutInfo
                            .padding(CELL_PADDING)
                            .tileStyle()
                        setsPerMuscleGroup
                            .padding(CELL_PADDING)
                            .tileStyle()
                    }
                }

                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("exercises", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WorkoutSetGroupList(
                        workout: workout,
                        focusedIntegerFieldIndex: .constant(nil),
                        canReorder: false
                    )
                    .canEdit(false)
                }

                if canNavigateToTemplate {
                    VStack(spacing: SECTION_HEADER_SPACING) {
                        Text(NSLocalizedString("template", comment: ""))
                            .sectionHeaderStyle2()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        templateButton
                        Text(NSLocalizedString("templateExplanation", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondaryLabel)
                            .padding(.vertical, 10)
                            .padding(.horizontal)
                    }
                    .buttonStyle(BigButtonStyle())
                }
            }
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            .padding(.horizontal)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(
                        action: {
                            sheetType = .workoutEditor
                        },
                        label: {
                            Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
                        }
                    )
                    Button(
                        role: .destructive,
                        action: {
                            isShowingDeleteWorkoutAlert = true
                        }
                    ) {
                        Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            NSLocalizedString("deleteWorkoutDescription", comment: ""),
            isPresented: $isShowingDeleteWorkoutAlert,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("deleteWorkout", comment: ""), role: .destructive) {
                database.delete(workout, saveContext: true)
                dismiss()
            }
        }
        .sheet(item: $sheetType) { type in
            switch type {
            case .newTemplateFromWorkout:
                TemplateEditorScreen(
                    template: database.newTemplate(from: workout),
                    isEditingExistingTemplate: false
                )
            case .templateDetail:
                NavigationStack {
                    TemplateDetailScreen(template: workout.template!)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(NSLocalizedString("navBack", comment: "")) {
                                    sheetType = nil
                                }
                            }
                        }
                }
            case .workoutEditor:
                WorkoutEditorScreen(workout: workout, isAddingNewWorkout: false)
            }
        }
    }

    // MARK: - Supporting Views

    private var workoutHeader: some View {
        VStack(alignment: .leading) {
            Text(workout.date?.description(.long) ?? "")
                .screenHeaderTertiaryStyle()
            Text(workout.name ?? "")
                .screenHeaderStyle()
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workoutInfo: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("starttime", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text("\(workout.date?.timeString ?? "")")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("duration", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text("\(workoutDurationString)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("exercises", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text("\(workout.numberOfSetGroups)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("sets", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text("\(workout.numberOfSets)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var setsPerMuscleGroup: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(NSLocalizedString("muscleGroups", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.tint)
                    .rotationEffect(isMuscleGroupExpanded ? .degrees(90) : .degrees(0))
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("focus", comment: ""))
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .fontWeight(.semibold)
                        HStack {
                            ForEach(getFocusedMuscleGroups()) { muscleGroup in
                                Text(muscleGroup.description)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(muscleGroup.color)
                            }
                        }
                    }
                    .emptyPlaceholder(getMuscleGroupOccurancesInWorkout) {
                        Text(NSLocalizedString("noWorkoutsThisWeek", comment: ""))
                            .font(.body)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                    MuscleGroupOccurancesChart(muscleGroupOccurances: getMuscleGroupOccurancesInWorkout)
                        .frame(width: 70, height: 70)
                }
                if isMuscleGroupExpanded {
                    VStack(spacing: CELL_SPACING) {
                        ForEach(getMuscleGroupOccurancesInWorkout, id: \.self.0) { muscleGroupOccurance in
                            HStack {
                                Text(muscleGroupOccurance.0.description)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(muscleGroupOccurance.0.color)
                                Spacer()
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading) {
                                        Text(NSLocalizedString("exercises", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(workout.setGroups.filter { $0.muscleGroups.contains(where: { $0 == muscleGroupOccurance.0 }) }.count)")
                                            .fontWeight(.bold)
                                            .fontDesign(.rounded)
                                    }
                                    Divider()
                                    VStack(alignment: .leading) {
                                        Text(NSLocalizedString("sets", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(workout.sets.filter { $0.setGroup?.muscleGroups.contains(where: { $0 == muscleGroupOccurance.0 }) ?? false }.count)")
                                            .fontWeight(.bold)
                                            .fontDesign(.rounded)
                                    }
                                    Divider()
                                    VStack(alignment: .leading) {
                                        Text(NSLocalizedString("volume", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        UnitView(
                                            value: "\(convertWeightForDisplaying(volume(for: muscleGroupOccurance.0, in: workout.sets)))",
                                            unit: WeightUnit.used.rawValue.uppercased()
                                        )
                                    }
                                }
                            }
                            .padding(CELL_PADDING)
                            .secondaryTileStyle(backgroundColor: muscleGroupOccurance.0.color.secondaryTranslucentBackground)
                        }
                    }
                }
            }
            .isBlockedWithoutPro()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isMuscleGroupExpanded.toggle()
            }
        }
    }

    private var templateButton: some View {
        Button {
            sheetType = workout.template != nil ? .templateDetail : .newTemplateFromWorkout
        } label: {
            HStack {
                if workout.template == nil {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                }
                Text(
                    workout.template?.name
                        ?? NSLocalizedString("newTemplateFromWorkout", comment: "")
                )
                .fontWeight(.medium)
                .lineLimit(1)
                if workout.template != nil {
                    Spacer()
                    NavigationChevron()
                } else {
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - Computed Properties

    private var workoutDurationString: String {
        guard let start = workout.date, let end = workout.endDate else { return "0:00" }
        let hours = Calendar.current.dateComponents([.hour], from: start, to: end).hour ?? 0
        let minutes =
            (Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0) % 60
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
    }

    var getMuscleGroupOccurancesInWorkout: [(MuscleGroup, Int)] {
        muscleGroupService.getMuscleGroupOccurances(in: workout)
    }

    private var amountOfOccurances: Int {
        getMuscleGroupOccurancesInWorkout.reduce(0) { $0 + $1.1 }
    }

    /// Calculates the smallest number of Muscle Groups that combined account for 51% of the overall sets in the timeframe
    /// - Returns: The focused Muscle Groups
    private func getFocusedMuscleGroups() -> [MuscleGroup] {
        var accumulatedPercetange: Float = 0
        var focusedMuscleGroups = [MuscleGroup]()
        for muscleGroupOccurance in getMuscleGroupOccurancesInWorkout {
            accumulatedPercetange += Float(muscleGroupOccurance.1) / Float(amountOfOccurances)
            focusedMuscleGroups.append(muscleGroupOccurance.0)
            if accumulatedPercetange > 0.51 {
                return Array(focusedMuscleGroups.prefix(2))
            }
        }
        return []
    }

    private func volume(for muscleGroup: MuscleGroup, in sets: [WorkoutSet]) -> Int {
        sets.reduce(0) { currentVolume, currentSet in
            if let standardSet = currentSet as? StandardSet {
                guard standardSet.exercise?.muscleGroup == muscleGroup else { return currentVolume }
                return currentVolume + Int(standardSet.repetitions * standardSet.weight)
            }
            if let dropSet = currentSet as? DropSet, let repetitions = dropSet.repetitions, let weights = dropSet.weights {
                guard dropSet.exercise?.muscleGroup == muscleGroup else { return currentVolume }
                return currentVolume + Int(zip(repetitions, weights).map(*).reduce(0, +))
            }
            if let superSet = currentSet as? SuperSet {
                var volumeForFirstExercise = 0
                var volumeForSecondExercise = 0
                if superSet.exercise?.muscleGroup == muscleGroup {
                    volumeForFirstExercise = Int(superSet.repetitionsFirstExercise * superSet.weightFirstExercise)
                }
                if superSet.secondaryExercise?.muscleGroup == muscleGroup {
                    volumeForSecondExercise = Int(superSet.repetitionsSecondExercise * superSet.weightSecondExercise)
                }
                return currentVolume + volumeForFirstExercise + volumeForSecondExercise
            }
            return currentVolume
        }
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject var database: Database

    var body: some View {
        NavigationStack {
            WorkoutDetailScreen(
                workout: database.testWorkout,
                canNavigateToTemplate: false
            )
        }
    }
}

struct WorkoutDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
