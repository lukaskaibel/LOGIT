//
//  ExerciseDetailScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.01.22.
//

import Charts
import CoreData
import SwiftUI

struct ExerciseDetailScreen: View {

    enum TimeSpan {
        case threeMonths, year, allTime
    }

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var database: Database
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    @EnvironmentObject private var workoutSetGroupRepository: WorkoutSetGroupRepository

    // MARK: - State

    @State private var selectedTimeSpanForWeight: DateLineChart.DateDomain = .threeMonths
    @State private var selectedTimeSpanForRepetitions: DateLineChart.DateDomain = .threeMonths
    @State private var selectedTimeSpanForVolume: DateLineChart.DateDomain = .threeMonths
    @State private var selectedTimeSpanForSetsPerWeek: DateLineChart.DateDomain = .threeMonths
    @State private var showDeletionAlert = false
    @State private var showingEditExercise = false
    @State private var isShowingExerciseHistoryScreen = false
    @State private var isShowingWeightScreen = false
    @State private var isShowingRepetitionsScreen = false
    @State private var isShowingVolumeScreen = false

    // MARK: - Variables

    let exercise: Exercise

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                header
                    .padding(.horizontal)
                
                VStack {
                    Button {
                        isShowingWeightScreen = true
                    } label: {
                        ExerciseWeightTile(exercise: exercise)
                    }
                    .buttonStyle(TileButtonStyle())
                    Button {
                        isShowingRepetitionsScreen = true
                    } label: {
                        ExerciseRepetitionsTile(exercise: exercise)
                    }
                    .buttonStyle(TileButtonStyle())
                    Button {
                        isShowingVolumeScreen = true
                    } label: {
                        ExerciseVolumeTile(exercise: exercise)
                    }
                    .buttonStyle(TileButtonStyle())
                }
                .padding(.horizontal)
                
//                WidgetCollectionView(
//                    type: .exerciseDetail,
//                    title: NSLocalizedString("overview", comment: ""),
//                    views: [
//                        exerciseInfo.widget(ofType: .personalBest, isAddedByDefault: true),
//                        weightGraph.widget(ofType: .bestWeightPerDay, isAddedByDefault: true),
//                        repetitionsGraph.widget(ofType: .bestRepetitionsPerDay, isAddedByDefault: false),
//                        volumePerDayGraph.widget(ofType: .volumePerDay, isAddedByDefault: false),
//                        setsPerWeekGraph.widget(ofType: .exerciseSetsPerWeek, isAddedByDefault: false)
//                    ],
//                    database: database
//                )
//                .padding(.horizontal)

                Button {
                    isShowingExerciseHistoryScreen = true
                } label: {
                    HStack {
                        Text(NSLocalizedString("history", comment: ""))
                            .fontWeight(.semibold)
                        Spacer()
                        NavigationChevron()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(CELL_PADDING)
                    .tileStyle()
                }
                .padding(.horizontal)
            }
            .animation(.easeInOut)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(exercise.muscleGroup?.color ?? .accentColor)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(
                        action: { showingEditExercise.toggle() },
                        label: {
                            Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
                        }
                    )
                    Button(
                        role: .destructive,
                        action: { showDeletionAlert.toggle() },
                        label: {
                            Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
                        }
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            Text(NSLocalizedString("deleteExerciseConfirmation", comment: "")),
            isPresented: $showDeletionAlert,
            titleVisibility: .visible
        ) {
            Button(
                "\(NSLocalizedString("delete", comment: ""))",
                role: .destructive,
                action: {
                    database.delete(exercise, saveContext: true)
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingEditExercise) {
            ExerciseEditScreen(exerciseToEdit: exercise)
        }
        .navigationDestination(isPresented: $isShowingExerciseHistoryScreen) {
            ExerciseHistoryScreen(exercise: exercise)
        }
        .navigationDestination(isPresented: $isShowingWeightScreen) {
            ExerciseWeightScreen(exercise: exercise)
        }
        .navigationDestination(isPresented: $isShowingRepetitionsScreen) {
            ExerciseRepetitionsScreen(exercise: exercise)
        }
        .navigationDestination(isPresented: $isShowingVolumeScreen) {
            ExerciseVolumeScreen(exercise: exercise)
        }
    }

    // MARK: - Supporting Views

    private var header: some View {
        VStack(alignment: .leading) {
            Text(exercise.name ?? "")
                .screenHeaderStyle()
                .lineLimit(2)
            Text(exercise.muscleGroup?.description.capitalized ?? "")
                .screenHeaderSecondaryStyle()
                .foregroundStyle((exercise.muscleGroup?.color ?? .clear).gradient)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
//    private var setsPerWeekGraph: some View {
//        VStack {
//            VStack(alignment: .leading) {
//                Text(NSLocalizedString("sets", comment: ""))
//                    .tileHeaderStyle()
//                Text(NSLocalizedString("PerWeek", comment: ""))
//                    .tileHeaderSecondaryStyle()
//            }
//            .frame(maxWidth: .infinity, alignment: .leading)
//            DateBarChart(dateUnit: .weekOfYear) {
//                workoutSetRepository.getGroupedWorkoutsSets(with: exercise, in: .weekOfYear)
//                    .compactMap {
//                        guard let date = $0.first?.workout?.date else { return nil }
//                        return .init(date: date, value: $0.count)
//                    }
//            }
//            .foregroundStyle((exercise.muscleGroup?.color.gradient) ?? Color.accentColor.gradient)
//        }
//        .padding(CELL_PADDING)
//        .tileStyle()
//    }

    // MARK: - Computed Properties

    private func personalBest(for attribute: WorkoutSet.Attribute) -> Int {
        workoutSetRepository.getWorkoutSets(with: exercise)
            .map {
                attribute == .repetitions
                    ? $0.max(.repetitions) : convertWeightForDisplaying($0.max(.weight))
            }
            .max() ?? 0
    }

    private func max(_ attribute: WorkoutSet.Attribute, in workoutSet: WorkoutSet) -> Int {
        if let standardSet = workoutSet as? StandardSet {
            return Int(attribute == .repetitions ? standardSet.repetitions : standardSet.weight)
        }
        if let dropSet = workoutSet as? DropSet {
            return Int(
                (attribute == .repetitions ? dropSet.repetitions : dropSet.weights)?.max() ?? 0
            )
        }
        if let superSet = workoutSet as? SuperSet {
            if superSet.setGroup?.exercise == exercise {
                return Int(
                    attribute == .repetitions
                        ? superSet.repetitionsFirstExercise : superSet.weightFirstExercise
                )
            } else {
                return Int(
                    attribute == .repetitions
                        ? superSet.repetitionsSecondExercise : superSet.weightSecondExercise
                )
            }
        }
        return 0
    }

    private var firstPerformedOverOneYearAgo: Bool {
        Calendar.current.date(byAdding: .year, value: -1, to: .now)!
            > workoutSetRepository.getWorkoutSets(with: exercise).compactMap({ $0.setGroup?.workout?.date })
            .min()
            ?? .now
    }

//    private func setsForExercise(
//        withHeighest attribute: WorkoutSet.Attribute,
//        withoutZeroRepetitions: Bool = false,
//        withoutZeroWeights: Bool = false
//    ) -> [WorkoutSet] {
//        workoutSetRepository.getWorkoutSets(with: exercise, onlyHighest: attribute, in: .day)
//            .filter { !withoutZeroRepetitions || $0.max(.repetitions) > 0 }
//            .filter { !withoutZeroWeights || $0.max(.weight) > 0 }
//    }

    

}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationStack {
            ExerciseDetailScreen(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
