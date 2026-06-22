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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var isShowingE1RMScreen = false
    @State private var isShowingRepetitionsScreen = false
    @State private var isShowingVolumeScreen = false
    @State private var isShowingSetVolumeScreen = false
    @State private var isShowingSetsScreen = false
    @State private var isShowingInstructions = false
    @State private var isShowingMergingSheet = false
    @State private var mergedIntoExercise: Exercise?
    /// Guards `autoOpenMetric` so it pushes the metric chart only on first appearance — `onAppear`
    /// also fires when popping back from that chart, which would otherwise re-push it endlessly.
    @State private var hasAutoOpenedMetric = false

    // MARK: - Variables

    @StateObject var exercise: Exercise
    var isShowingAsSheet: Bool = false
    var scrollToRecentAttempts: Bool = false
    /// When set, the corresponding metric screen is pushed automatically on appear — used by the
    /// in-workout metric badge's popover to jump straight to the tapped metric's chart.
    var autoOpenMetric: ExercisePrimaryMetric? = nil
    var onNavigateToExercise: ((Exercise) -> Void)?

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            WorkoutSetGroup.self,
            sortDescriptors: [SortDescriptor(\.workout?.date, order: .reverse)],
            predicate: WorkoutSetGroupPredicateFactory.getWorkoutSetGroups(withExercise: exercise)
        ) { workoutSetGroups in
            let recentWorkoutSetGroups = workoutSetGroups.prefix(3)
            let workoutSets = workoutSetGroups.flatMap { $0.sets }
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: SECTION_SPACING) {
                    header
                        .padding(.horizontal)

                    metricTiles(workoutSets: workoutSets)
                        .padding(.horizontal)

                    VStack(spacing: SECTION_HEADER_SPACING) {
                        HStack {
                            Text(NSLocalizedString("recentAttempts", comment: ""))
                                .sectionHeaderStyle2()
                            Spacer()
                        }
                        .id("recentAttempts")
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
                .animation(.easeInOut, value: workoutSetGroups)
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
                        Button {
                            isShowingInstructions = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        Menu {
                            Button {
                                isShowingMergingSheet = true
                            } label: {
                                Label(NSLocalizedString("mergeExercise", comment: ""), systemImage: "arrow.triangle.merge")
                            }
                            if !exercise.isDefaultExercise {
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
                            }
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
            .sheet(isPresented: $showingEditExercise) {
                ExerciseEditScreen(exerciseToEdit: exercise)
            }
            .sheet(isPresented: $isShowingInstructions) {
                ExerciseInstructionsSheet(exercise: exercise)
            }
            .sheet(isPresented: $isShowingMergingSheet) {
                ExerciseMergingSheet(exercise: exercise) { targetExercise in
                    if targetExercise != exercise {
                        if isShowingAsSheet {
                            onNavigateToExercise?(targetExercise)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                dismiss()
                            }
                        } else {
                            mergedIntoExercise = targetExercise
                        }
                    }
                }
            }
            .navigationDestination(item: $mergedIntoExercise) { targetExercise in
                ExerciseDetailScreen(exercise: targetExercise)
            }
            .navigationDestination(isPresented: $isShowingExerciseHistoryScreen) {
                ExerciseHistoryScreen(exercise: exercise)
            }
            .navigationDestination(isPresented: $isShowingWeightScreen) {
                ExerciseWeightScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .navigationDestination(isPresented: $isShowingE1RMScreen) {
                ExerciseE1RMScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .navigationDestination(isPresented: $isShowingRepetitionsScreen) {
                ExerciseRepetitionsScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .navigationDestination(isPresented: $isShowingVolumeScreen) {
                ExerciseVolumeScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .navigationDestination(isPresented: $isShowingSetVolumeScreen) {
                ExerciseSetVolumeScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .navigationDestination(isPresented: $isShowingSetsScreen) {
                ExerciseSetsScreen(exercise: exercise, workoutSets: workoutSets)
            }
            .onAppear {
                if let autoOpenMetric, !hasAutoOpenedMetric {
                    hasAutoOpenedMetric = true
                    DispatchQueue.main.async {
                        switch autoOpenMetric {
                        case .estimatedOneRepMax: isShowingE1RMScreen = true
                        case .weight: isShowingWeightScreen = true
                        case .repetitions: isShowingRepetitionsScreen = true
                        }
                    }
                }
                guard scrollToRecentAttempts else { return }
                DispatchQueue.main.async {
                    scrollProxy.scrollTo("recentAttempts", anchor: .top)
                }
            }
            }
        }
    }

    // MARK: - Supporting Views

    /// The metric tiles in the in-workout popover's compact language: the four "current best"
    /// metrics as a two-column grid, with the weekly volume tile full-width beneath — its bars
    /// need the room, and "this week" is a different kind of stat than the best-value tiles.
    /// Collapses to one column at accessibility type sizes, where half-width tiles can't fit
    /// their text.
    @ViewBuilder
    private func metricTiles(workoutSets: [WorkoutSet]) -> some View {
        let spacing: CGFloat = 10
        // No logged sets yet (a workout being recorded doesn't count — the tiles exclude it):
        // one friendly placeholder instead of five identical "––" skeletons.
        if !workoutSets.contains(where: { $0.workout?.isCurrentWorkout != true }) {
            ExerciseMetricsEmptyTile(color: exercise.muscleGroup?.color ?? .accentColor)
        } else {
            VStack(spacing: spacing) {
                if dynamicTypeSize.isAccessibilitySize {
                    weightTile(workoutSets: workoutSets)
                    e1RMTile(workoutSets: workoutSets)
                    repetitionsTile(workoutSets: workoutSets)
                    setVolumeTile(workoutSets: workoutSets)
                    volumeTile(workoutSets: workoutSets)
                    setsTile(workoutSets: workoutSets)
                } else {
                    HStack(alignment: .top, spacing: spacing) {
                        weightTile(workoutSets: workoutSets)
                        e1RMTile(workoutSets: workoutSets)
                    }
                    HStack(alignment: .top, spacing: spacing) {
                        repetitionsTile(workoutSets: workoutSets)
                        setVolumeTile(workoutSets: workoutSets)
                    }
                    // Volume (weekly tonnage) and Sets (weekly working-set count) are the two
                    // "this week vs last" workload stats — half-width siblings, not one wide tile.
                    HStack(alignment: .top, spacing: spacing) {
                        volumeTile(workoutSets: workoutSets)
                        setsTile(workoutSets: workoutSets)
                    }
                }
            }
        }
    }

    private func weightTile(workoutSets: [WorkoutSet]) -> some View {
        Button {
            isShowingWeightScreen = true
        } label: {
            ExerciseWeightTile(exercise: exercise, workoutSets: workoutSets)
        }
        .buttonStyle(TileButtonStyle())
    }

    private func e1RMTile(workoutSets: [WorkoutSet]) -> some View {
        Button {
            isShowingE1RMScreen = true
        } label: {
            ExerciseE1RMTile(exercise: exercise, workoutSets: workoutSets)
        }
        .buttonStyle(TileButtonStyle())
    }

    private func repetitionsTile(workoutSets: [WorkoutSet]) -> some View {
        Button {
            isShowingRepetitionsScreen = true
        } label: {
            ExerciseRepetitionsTile(exercise: exercise, workoutSets: workoutSets)
        }
        .buttonStyle(TileButtonStyle())
    }

    private func setVolumeTile(workoutSets: [WorkoutSet]) -> some View {
        Button {
            isShowingSetVolumeScreen = true
        } label: {
            ExerciseSetVolumeTile(exercise: exercise, workoutSets: workoutSets)
        }
        .buttonStyle(TileButtonStyle())
    }

    private func volumeTile(workoutSets: [WorkoutSet]) -> some View {
        Button {
            isShowingVolumeScreen = true
        } label: {
            ExerciseVolumeTile(exercise: exercise, workoutSets: workoutSets)
        }
        .buttonStyle(TileButtonStyle())
    }

    private func setsTile(workoutSets: [WorkoutSet]) -> some View {
        Button {
            isShowingSetsScreen = true
        } label: {
            ExerciseSetsTile(exercise: exercise, workoutSets: workoutSets)
        }
        .buttonStyle(TileButtonStyle())
    }

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
    
    private var hasInstructions: Bool {
        if let instructions = exercise.instructions, !instructions.isEmpty {
            return true
        }
        return false
    }
    
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
                    }
                    
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
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle(hasInstructions ? NSLocalizedString("instructions", comment: "") : exercise.displayName)
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
