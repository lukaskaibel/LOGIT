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
                
                VStack(spacing: SECTION_HEADER_SPACING) {
                    HStack {
                        Text(NSLocalizedString("recentAttempts", comment: ""))
                            .sectionHeaderStyle2()
                        Spacer()
                        Button {
                            isShowingExerciseHistoryScreen = true
                        } label: {
                            HStack {
                                Text(NSLocalizedString("all", comment: ""))
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                            }
                            .fontWeight(.semibold)
                        }
                    }
                    VStack(spacing: CELL_SPACING) {
                        ForEach(recentAttempts) { setGroup in
                            WorkoutSetGroupCell(
                                setGroup: setGroup,
                                focusedIntegerFieldIndex: .constant(nil),
                                sheetType: .constant(nil),
                                isReordering: .constant(false),
                                supplementaryText:
                                    "\(setGroup.workout?.date?.description(.short) ?? "")  ·  \(setGroup.workout?.name ?? "")"
                            )
                            .canEdit(false)
                            .padding(CELL_PADDING)
                            .tileStyle()
                            .shadow(color: .black.opacity(0.5), radius: 10)
                        }
                        .emptyPlaceholder(recentAttempts) {
                            Text(NSLocalizedString("noAttempts", comment: ""))
                        }
                    }
                }
                .padding()
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                .background(Color.secondaryBackground)
            }
            .animation(.easeInOut)
        }
        .edgesIgnoringSafeArea(.bottom)
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

    // MARK: - Computed Properties
    
    private var recentAttempts: [WorkoutSetGroup] {
        Array(workoutSetGroupRepository.getWorkoutSetGroups(with: exercise).prefix(3))
    }

    private func personalBest(for attribute: WorkoutSet.Attribute) -> Int {
        workoutSetRepository.getWorkoutSets(with: exercise)
            .map {
                attribute == .repetitions
                ? $0.maximum(.repetitions, for: exercise) : convertWeightForDisplaying($0.maximum(.weight, for: exercise))
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
