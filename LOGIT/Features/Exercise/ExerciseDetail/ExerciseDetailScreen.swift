//
//  ExerciseDetailScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.01.22.
//

import Charts
import ColorfulX
import CoreData
import SafariServices
import SwiftUI

struct ExerciseDetailScreen: View {
    enum TimeSpan {
        case threeMonths, year, allTime
    }

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var database: Database

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
    @State private var isShowingInstructions = false

    // MARK: - Variables

    @StateObject var exercise: Exercise
    var isShowingAsSheet: Bool = false

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            WorkoutSetGroup.self,
            sortDescriptors: [SortDescriptor(\.workout?.date, order: .reverse)],
            predicate: WorkoutSetGroupPredicateFactory.getWorkoutSetGroups(withExercise: exercise)
        ) { workoutSetGroups in
            let recentWorkoutSetGroups = workoutSetGroups.prefix(3)
            let workoutSets = workoutSetGroups.flatMap { $0.sets }
            ScrollView {
                VStack(spacing: SECTION_SPACING) {
                    header
                        .padding(.horizontal)

                    VStack {
                        Button {
                            isShowingWeightScreen = true
                        } label: {
                            ExerciseWeightTile(exercise: exercise, workoutSets: workoutSets)
                        }
                        .buttonStyle(TileButtonStyle())
                        Button {
                            isShowingRepetitionsScreen = true
                        } label: {
                            ExerciseRepetitionsTile(exercise: exercise, workoutSets: workoutSets)
                        }
                        .buttonStyle(TileButtonStyle())
                        Button {
                            isShowingVolumeScreen = true
                        } label: {
                            ExerciseVolumeTile(exercise: exercise, workoutSets: workoutSets)
                        }
                        .buttonStyle(TileButtonStyle())
                    }
                    .padding(.horizontal)

                    VStack(spacing: SECTION_HEADER_SPACING) {
                        HStack {
                            Text(NSLocalizedString("recentAttempts", comment: ""))
                                .sectionHeaderStyle2()
                            Spacer()
                        }
                        VStack(spacing: CELL_SPACING + 5) {
                            ForEach(recentWorkoutSetGroups) { setGroup in
                                ExerciseAttemptCell(setGroup: setGroup)
                            }
                            .emptyPlaceholder(recentWorkoutSetGroups) {
                                Text(NSLocalizedString("noAttempts", comment: ""))
                            }
                            
                            if !recentWorkoutSetGroups.isEmpty {
                                Button {
                                    isShowingExerciseHistoryScreen = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.title3)
                                            .foregroundStyle((exercise.muscleGroup?.color ?? .accentColor).gradient)
                                            .frame(width: 32, height: 32)
                                        Text(NSLocalizedString("showAllAttempts", comment: ""))
                                            .foregroundStyle(Color.label)
                                        Spacer()
                                        NavigationChevron()
                                            .foregroundStyle(Color.secondaryLabel)
                                    }
                                    .padding(CELL_PADDING)
                                    .tileStyle()
                                }
                                .buttonStyle(TileButtonStyle())
                            }
                        }
                        .padding(.top, 5)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                }
                .animation(.easeInOut)
            }
            .background(
                VStack {
                    ColorfulView(color: [exercise.muscleGroup?.color ?? .accentColor, .black], speed: .constant(0))
                        .mask(
                            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(height: 300)
                    Spacer()
                }
                .ignoresSafeArea(.all)
            )
            .edgesIgnoringSafeArea(.bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isShowingAsSheet {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .tint(exercise.muscleGroup?.color ?? .accentColor)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if let instructions = exercise.instructions, !instructions.isEmpty {
                            Button {
                                isShowingInstructions = true
                            } label: {
                                Image(systemName: "info.circle")
                            }
                        }
                        if !exercise.isDefaultExercise {
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
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEditExercise) {
                ExerciseEditScreen(exerciseToEdit: exercise)
            }
            .sheet(isPresented: $isShowingInstructions) {
                ExerciseInstructionsSheet(exercise: exercise)
            }
            .navigationDestination(isPresented: $isShowingExerciseHistoryScreen) {
                ExerciseHistoryScreen(exercise: exercise)
            }
            .navigationDestination(isPresented: $isShowingWeightScreen) {
                ExerciseWeightScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .navigationDestination(isPresented: $isShowingRepetitionsScreen) {
                ExerciseRepetitionsScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .navigationDestination(isPresented: $isShowingVolumeScreen) {
                ExerciseVolumeScreen(exercise: exercise, workoutSets: workoutSets)
            }
        }
    }

    // MARK: - Supporting Views

    private var header: some View {
        VStack(alignment: .leading) {
            Text(exercise.displayName)
                .screenHeaderStyle()
                .lineLimit(2)
            Text(exercise.muscleGroup?.description.capitalized ?? "")
                .screenHeaderSecondaryStyle()
                .foregroundStyle((exercise.muscleGroup?.color ?? .clear).gradient)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Computed Properties

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

// MARK: - Exercise Instructions Sheet

struct ExerciseInstructionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var safariURL: URL?
    
    let exercise: Exercise
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let instructions = exercise.instructions, !instructions.isEmpty {
                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(exercise.muscleGroup?.color ?? .accentColor)
                                    .frame(width: 32, alignment: .leading)
                                
                                Text(instruction)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 16)
                            
                            if index < instructions.count - 1 {
                                Divider()
                            }
                        }
                        
                        Divider()
                            .padding(.top, 16)
                        
                        let exerciseName = exercise.displayName
                        if let searchQuery = exerciseName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://www.google.com/search?q=\(searchQuery)+\(NSLocalizedString("exercise", comment: ""))") {
                            Button {
                                safariURL = url
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(String(format: NSLocalizedString("lookupExercise", comment: ""), exerciseName))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(BigButtonStyle())
                            .padding(.vertical, 32)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle(NSLocalizedString("instructions", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $safariURL) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
