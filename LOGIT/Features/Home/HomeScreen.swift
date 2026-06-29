//
//  HomeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.09.21.
//

import ColorfulX
import CoreData
import SwiftUI

struct HomeScreen: View {
    // MARK: - AppStorage

    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = -1
    @AppStorage("pinnedMeasurements") private var pinnedMeasurementsData: Data = Data()
    @AppStorage("pinnedExercises") private var pinnedExercisesData: Data = Data()

    // MARK: - Environment

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @EnvironmentObject private var measurementController: MeasurementEntryController
    @EnvironmentObject private var database: Database

    // MARK: - State

    @StateObject private var summaryViewModel = SummaryViewModel()

    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingSettings = false
    @State private var isShowingMeasurementsEditSheet = false
    @State private var isShowingExercisesPinEditSheet = false
    @State private var isShowingMeasurementsTip = true
    @State private var isShowingExercisesTip = true
    @State private var isShowingStartWorkoutSheet = false
    @State private var summaryRecords: [WorkoutProgressReport.PRRecord] = []

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { workouts in
            NavigationStack(path: $homeNavigationCoordinator.path) {
                ScrollView {
                    VStack(spacing: 5) {
                        if #unavailable(iOS 26.0) {
                            header
                                .padding([.top, .horizontal])
                        }
                        VStack(spacing: SECTION_SPACING) {
                            if #unavailable(iOS 26.0) {
                                VStack(spacing: 0) {
                                    Button {
                                        homeNavigationCoordinator.path.append(.exerciseList)
                                    } label: {
                                        HStack {
                                            HStack {
                                                Image(systemName: "dumbbell")
                                                    .frame(width: 40)
                                                    .foregroundStyle(Color.accentColor)
                                                Text(NSLocalizedString("exercises", comment: ""))
                                                    .foregroundStyle(.white)
                                            }
                                            Spacer()
                                            NavigationChevron()
                                                .foregroundStyle(Color.secondaryLabel)
                                        }
                                        .padding(.trailing)
                                        .padding(.vertical, 12)
                                    }
                                    Divider()
                                        .padding(.leading, 45)
                                    Button {
                                        homeNavigationCoordinator.path.append(.templateList)
                                    } label: {
                                        HStack {
                                            HStack {
                                                Image(systemName: "list.bullet.rectangle.portrait")
                                                    .frame(width: 40)
                                                    .foregroundStyle(Color.accentColor)
                                                Text(NSLocalizedString("templates", comment: ""))
                                                    .foregroundStyle(.white)
                                            }
                                            Spacer()
                                            NavigationChevron()
                                                .foregroundStyle(Color.secondaryLabel)
                                        }
                                        .padding(.trailing)
                                        .padding(.vertical, 12)
                                    }
                                }
                                .font(.title2)
                                .padding(.horizontal)
                            }

                            if summaryViewModel.mode(workouts: workouts) == .firstOpen {
                                SummaryWelcomeView(
                                    onStartWorkout: { isShowingStartWorkoutSheet = true },
                                    onBrowseTemplates: { homeNavigationCoordinator.path.append(.templateList) }
                                )
                                .padding(.horizontal)
                            } else {
                            VStack(spacing: 8) {
                                weeklyGoalHero(workouts: workouts)
                                PeriodPicker(selection: Binding(
                                    get: { summaryViewModel.selectedPeriod },
                                    set: { summaryViewModel.userSelected($0) }
                                ))
                                .padding(.vertical, 2)
                                if summaryViewModel.didAutoFallback {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle")
                                        Text(summaryViewModel.selectedPeriod == .year
                                            ? NSLocalizedString("summaryEmptyWeekHintYear", comment: "")
                                            : NSLocalizedString("summaryEmptyWeekHintMonth", comment: ""))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                SummaryStatTileGrid(
                                    viewModel: summaryViewModel,
                                    workouts: workouts,
                                    onOpenDetail: { metric in
                                        homeNavigationCoordinator.path.append(.summaryStat(metric))
                                    }
                                )
                                Button {
                                    homeNavigationCoordinator.path.append(.muscleGroupsOverview)
                                } label: {
                                    MuscleBalanceTile(
                                        workouts: summaryViewModel.filtered(workouts, to: summaryViewModel.selectedPeriod),
                                        period: summaryViewModel.selectedPeriod
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(TileButtonStyle())
                                if !summaryRecords.isEmpty {
                                    Button {
                                        homeNavigationCoordinator.path.append(.summaryRecords(summaryViewModel.selectedPeriod))
                                    } label: {
                                        SummaryRecordsTile(
                                            records: summaryRecords,
                                            period: summaryViewModel.selectedPeriod
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(TileButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                            .onAppear {
                                summaryViewModel.resolveInitialPeriod(workouts: workouts)
                            }
                            .task(id: "\(summaryViewModel.selectedPeriod.rawValue)-\(workouts.count)") {
                                summaryRecords = SummaryRecords.records(
                                    in: summaryViewModel.filtered(workouts, to: summaryViewModel.selectedPeriod),
                                    database: database
                                )
                            }

                            exercisesSection
                                .padding(.horizontal)

                            measurementsSection
                                .padding(.horizontal)
                            }

                        }
                        .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                        .padding(.top)
                    }
                }
                .background(
                    VStack {
                        ColorfulView(color: MuscleGroup.allCases.map({ $0.color }), speed: .constant(0))
                            .mask(
                                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                                
                            )
                            .frame(height: 300)
                        Spacer()
                    }
                    .ignoresSafeArea(.all)
                )
                .sheet(isPresented: $isShowingSettings) {
                    NavigationStack {
                        SettingsScreen()
                            .navigationTitle(NSLocalizedString("settings", comment: ""))
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button(NSLocalizedString("done", comment: "")) {
                                        isShowingSettings = false
                                    }
                                }
                            }
                    }
                }
                .sheet(isPresented: $isShowingStartWorkoutSheet) {
                    WorkoutStartSheet()
                }
                .sheet(isPresented: $isShowingMeasurementsEditSheet) {
                    MeasurementsEditSheet(pinnedMeasurements: Binding(
                        get: { pinnedMeasurements },
                        set: { setPinnedMeasurements($0) }
                    ))
                }
                .sheet(isPresented: $isShowingExercisesPinEditSheet) {
                    ExercisesPinEditSheet(pinnedTiles: Binding(
                        get: { pinnedExerciseTiles },
                        set: { setPinnedExerciseTiles($0) }
                    ))
                }
                .navigationDestination(for: HomeNavigationDestinationType.self) { destination in
                    switch destination {
                    case let .exercise(exercise):
                        ExerciseDetailScreen(exercise: exercise)
                    case .exerciseList: ExerciseListScreen()
                    case let .measurementDetail(measurementType):
                        MeasurementDetailScreen(measurementType: measurementType)
                    case .measurements: MeasurementsScreen()
                    case .muscleGroupsOverview:
                        MuscleGroupsOverviewScreen()
                    case .muscleTargetSplit:
                        MuscleTargetSplitScreen()
                    case let .muscleGroupDetail(group):
                        MuscleGroupDetailScreen(muscleGroup: group)
                    case .overallSets: OverallSetsScreen(workouts: workouts)
                    case let .summaryStat(metric):
                        SummaryStatScreen(
                            metric: metric,
                            workouts: workouts,
                            initialPeriod: summaryViewModel.selectedPeriod
                        )
                    case let .summaryRecords(period):
                        SummaryRecordsScreen(
                            workouts: summaryViewModel.filtered(workouts, to: period),
                            period: period
                        )
                    case .targetPerWeek: TargetPerWeekDetailScreen()
                    case .weeklyGoal: WorkoutGoalScreen(workouts: workouts)
                    case let .template(template):
                        TemplateDetailScreen(template: template)
                    case .templateList: TemplateListScreen()
                    case .volume: VolumeScreen(workoutSets: workouts.flatMap(\.sets))
                    case let .workout(workout):
                        WorkoutDetailScreen(
                            workout: workout,
                            canNavigateToTemplate: true
                        )
                    case .workoutList: WorkoutListScreen()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .largeTitle) {
                        HStack {
                            Text(NSLocalizedString("summary", comment: ""))
                                .font(.largeTitle.bold())
                            Spacer()
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "person.circle")
                            }
                            .font(.title)
                            .foregroundStyle(.tint)
                        }
                    }
                }
                .navigationTitle("Summary")
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Supporting Views

    private var header: some View {
        VStack(alignment: .leading) {
            Text(Date.now.formatted(date: .long, time: .omitted))
                .screenHeaderTertiaryStyle()
            if !purchaseManager.hasUnlockedPro {
                Text("LOGIT")
                    .screenHeaderStyle()
            } else {
                LogitProLogo()
                    .screenHeaderStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @State private var isShowingWorkoutGoalSheet = false

    private func weeklyGoalHero(workouts: [Workout]) -> some View {
        Group {
            if targetPerWeek > 0 {
                Button {
                    homeNavigationCoordinator.path.append(.weeklyGoal)
                } label: {
                    WeeklyGoalHeroTile(workouts: workouts)
                }
                .buttonStyle(TileButtonStyle())
            } else {
                TipView(
                    title: NSLocalizedString("noWeeklyGoalTip", comment: ""),
                    description: NSLocalizedString("noWeeklyGoalTipDescription", comment: ""),
                    buttonAction: .init(
                        title: NSLocalizedString("setGoal", comment: ""),
                        action: { isShowingWorkoutGoalSheet = true }
                    ),
                    showDismissButton: false,
                    isShown: .constant(true)
                )
                .sheet(isPresented: $isShowingWorkoutGoalSheet) {
                    NavigationStack {
                        ChangeWeeklyWorkoutGoalScreen()
                    }
                }
            }
        }
    }

    // MARK: - Measurements Section

    private var pinnedMeasurements: [MeasurementEntryType] {
        guard let decoded = try? JSONDecoder().decode([String].self, from: pinnedMeasurementsData) else {
            return []
        }
        return decoded.compactMap { MeasurementEntryType(rawValue: $0) }
    }

    private func setPinnedMeasurements(_ newValue: [MeasurementEntryType]) {
        if let encoded = try? JSONEncoder().encode(newValue.map { $0.rawValue }) {
            pinnedMeasurementsData = encoded
        }
    }

    @ViewBuilder
    private var measurementsSection: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("measurements", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                if purchaseManager.hasUnlockedPro {
                    Button {
                        isShowingMeasurementsEditSheet = true
                    } label: {
                        Text(NSLocalizedString("edit", comment: ""))
                    }
                    .fontWeight(.semibold)
                }
            }
            VStack(spacing: 8) {
                if pinnedMeasurements.isEmpty {
                    MeasurementsEmptyState(onAdd: { isShowingMeasurementsEditSheet = true })
                } else {
                    MeasurementWatchlist(types: pinnedMeasurements) { measurementType in
                        homeNavigationCoordinator.path.append(.measurementDetail(measurementType))
                    }
                
                Button {
                    homeNavigationCoordinator.path.append(.measurements)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "ruler.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .rotationEffect(.degrees(-45))
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("showAllMeasurements", comment: ""))
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
            .isBlockedWithoutPro(!pinnedMeasurements.isEmpty)
        }
    }
    
    // MARK: - Exercises Section
    
    private var pinnedExerciseTiles: [PinnedExerciseTile] {
        guard let decoded = try? JSONDecoder().decode([PinnedExerciseTile].self, from: pinnedExercisesData) else {
            return []
        }
        return decoded
    }
    
    private func setPinnedExerciseTiles(_ newValue: [PinnedExerciseTile]) {
        if let encoded = try? JSONEncoder().encode(newValue) {
            pinnedExercisesData = encoded
        }
    }
    
    @ViewBuilder
    private var exercisesSection: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("pinnedExercises", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                Button {
                    isShowingExercisesPinEditSheet = true
                } label: {
                    Text(NSLocalizedString("edit", comment: ""))
                }
                .fontWeight(.semibold)
            }
            VStack(spacing: 8) {
                if pinnedExerciseTiles.isEmpty {
                    PinnedExercisesEmptyState(onAdd: { isShowingExercisesPinEditSheet = true })
                } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(pinnedExerciseTiles.prefix(4), id: \.id) { pinnedTile in
                        if let exercise = database.getExercise(byID: pinnedTile.exerciseID) {
                            pinnedExerciseTileView(for: exercise, tileType: pinnedTile.tileType)
                        }
                    }
                }
                
                Button {
                    homeNavigationCoordinator.path.append(.exerciseList)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("showAllExercises", comment: ""))
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
        }
    }
    
    @ViewBuilder
    private func pinnedExerciseTileView(for exercise: Exercise, tileType: ExerciseTileType) -> some View {
        FetchRequestWrapper(
            WorkoutSetGroup.self,
            sortDescriptors: [SortDescriptor(\.workout?.date, order: .reverse)],
            predicate: WorkoutSetGroupPredicateFactory.getWorkoutSetGroups(withExercise: exercise)
        ) { workoutSetGroups in
            let workoutSets = workoutSetGroups.flatMap { $0.sets }
            Button {
                homeNavigationCoordinator.path.append(.exercise(exercise))
            } label: {
                switch tileType {
                case .weight:
                    ExerciseWeightTile(exercise: exercise, workoutSets: workoutSets)
                case .repetitions:
                    ExerciseRepetitionsTile(exercise: exercise, workoutSets: workoutSets)
                case .volume:
                    ExerciseVolumeTile(exercise: exercise, workoutSets: workoutSets)
                case .setVolume:
                    ExerciseSetVolumeTile(exercise: exercise, workoutSets: workoutSets)
                case .estimatedOneRepMax:
                    ExerciseE1RMTile(exercise: exercise, workoutSets: workoutSets)
                }
            }
            .buttonStyle(TileButtonStyle())
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeScreen()
            .previewEnvironmentObjects()
    }
}
