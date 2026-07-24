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
    @State private var summaryRecords: [WorkoutProgressReport.ExerciseRecords] = []
    // Default to the tab a marketing screenshot asked for (`-UITEST_DEEPLINK
    // progress`) so the Progress capture opens without a visible tab flip;
    // real launches always start on This Week.
    @State private var selectedTab: SummaryTab =
        ScreenshotFixtures.deepLinkTarget == "progress" ? .progress : .thisWeek
    @State private var didApplyScreenshotDeepLink = false

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { workouts in
            NavigationStack(path: $homeNavigationCoordinator.path) {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 5) {
                        if #unavailable(iOS 26.0) {
                            header
                                .padding([.top, .horizontal])
                        } else {
                            // Top inset reproduces the standing space the former
                            // `.largeTitle` navigation-bar title occupied, so the row
                            // lands where it did before moving in-flow.
                            summaryHeader
                                .padding(.horizontal)
                                .padding(.top, 46)
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
                                SummaryTabPicker(selection: $selectedTab)
                                .padding(.vertical, 2)
                                if selectedTab == .thisWeek {
                                    weeklyGoalHero(workouts: workouts)
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
                                } else {
                                    SummaryProgressTab(workouts: workouts)
                                }
                            }
                            .padding(.horizontal)
                            .onAppear {
                                summaryViewModel.resolveInitialPeriod(workouts: workouts)
                                applyScreenshotDeepLinkIfNeeded(workouts: workouts)
                            }
                            .task(id: "\(summaryViewModel.selectedPeriod.rawValue)-\(workouts.count)") {
                                summaryRecords = SummaryRecords.records(
                                    in: summaryViewModel.filtered(workouts, to: summaryViewModel.selectedPeriod),
                                    database: database
                                )
                            }

                            if selectedTab == .progress {
                                // Fixed scroll anchor for the Progress marketing
                                // screenshot (see the `.task` on the ScrollView).
                                Color.clear
                                    .frame(height: 1)
                                    .id("screenshotPinnedAnchor")
                                exercisesSection
                                    .padding(.horizontal)

                                measurementsSection
                                    .padding(.horizontal)
                            }
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
                    case let .muscleGroupDetail(group, initialPeriod):
                        MuscleGroupDetailScreen(muscleGroup: group, initialPeriod: initialPeriod)
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
                    case let .workout(workout):
                        WorkoutDetailScreen(
                            workout: workout,
                            canNavigateToTemplate: true
                        )
                    case .workoutList: WorkoutListScreen()
                    }
                }
                .navigationTitle(NSLocalizedString("summary", comment: ""))
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    // Screenshot-only, deterministic scroll for the Progress
                    // capture: once the tab has laid out and seeded its pins, jump
                    // to a fixed anchor so the pinned tiles clear the Start Workout
                    // bar while the Highlights stay in view. The UI test can't do
                    // this — its gesture flick travels an unpredictable, per-run
                    // distance — so the app positions it instead. No-op for real
                    // users (guarded on the fixtures + deep-link flags).
                    guard ScreenshotFixtures.isEnabled,
                          ScreenshotFixtures.deepLinkTarget == "progress" else { return }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    proxy.scrollTo("screenshotPinnedAnchor", anchor: UnitPoint(x: 0.5, y: 0.63))
                }
                }
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

    /// The Summary large-title row (title + settings avatar). Rendered as in-flow
    /// scroll content rather than a `ToolbarItem(placement: .largeTitle)`: custom
    /// large-title toolbar content is not exposed to the accessibility tree on
    /// iOS 26 (the navigation bar reports zero children), so VoiceOver / UI
    /// automation could never reach the settings button. In-flow content keeps the
    /// identical look while staying fully accessible.
    private var summaryHeader: some View {
        HStack {
            Text(NSLocalizedString("summary", comment: ""))
                .font(.largeTitle.bold())
            Spacer()
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "person.circle")
                    .imageScale(.large)
            }
            .font(.title)
            .foregroundStyle(.tint)
            .accessibilityLabel(NSLocalizedString("settings", comment: ""))
            .accessibilityIdentifier("settingsButton")
        }
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

    // MARK: - Marketing screenshot deep links

    /// Opens the screen named by `-UITEST_DEEPLINK` once the summary has data.
    /// Detail targets push onto the nav path; `progress` is already handled by
    /// `selectedTab`'s initial value. Gated on `ScreenshotFixtures.isEnabled`
    /// so this can never run for a real user (App Store builds can't be handed
    /// launch arguments anyway).
    private func applyScreenshotDeepLinkIfNeeded(workouts: [Workout]) {
        guard ScreenshotFixtures.isEnabled,
              !didApplyScreenshotDeepLink,
              let target = ScreenshotFixtures.deepLinkTarget else { return }
        didApplyScreenshotDeepLink = true
        switch target {
        case "progress":
            // selectedTab is already .progress (its initial value); pin a few
            // seeded lifts so the Progress tab shows real, climbing tiles
            // instead of the empty-state teaser.
            let all = (database.fetch(Exercise.self) as? [Exercise]) ?? []
            let tiles: [PinnedExerciseTile] = ["previewBenchPress", "previewSquat", "previewDeadlift", "previewOverheadPress"].compactMap { key in
                let name = NSLocalizedString(key, comment: "")
                guard let id = all.first(where: { $0.name == name })?.id else { return nil }
                return PinnedExerciseTile(exerciseID: id, tileType: .estimatedOneRepMax)
            }
            setPinnedExerciseTiles(tiles)
            // Pin the two seeded measurements (bodyweight + body fat) so the
            // watchlist shows real trends instead of the empty-state teaser.
            setPinnedMeasurements([.bodyweight, .bodyFatPercentage])
        case "goal":
            homeNavigationCoordinator.path = [.weeklyGoal]
        case "muscleOverview":
            homeNavigationCoordinator.path = [.muscleGroupsOverview]
        case "measurement":
            homeNavigationCoordinator.path = [.measurementDetail(.bodyFatPercentage)]
        case "exerciseDetail":
            if let exercise = screenshotFixtureExercise(named: "previewBenchPress") {
                homeNavigationCoordinator.path = [.exercise(exercise)]
            }
        case "workoutDetail":
            if let workout = screenshotFixtureWorkout(named: "previewArmDay", in: workouts) {
                homeNavigationCoordinator.path = [.workout(workout)]
            }
        default:
            break // unknown values no-op.
        }
    }

    /// Resolves a seeded fixture exercise by its localized name (the app can
    /// read its own `NSLocalizedString`, so this stays correct in every
    /// capture locale), falling back to the first exercise.
    private func screenshotFixtureExercise(named key: String) -> Exercise? {
        let name = NSLocalizedString(key, comment: "")
        let all = (database.fetch(Exercise.self) as? [Exercise]) ?? []
        return all.first { $0.name == name } ?? all.first
    }

    private func screenshotFixtureWorkout(named key: String, in workouts: [Workout]) -> Workout? {
        let name = NSLocalizedString(key, comment: "")
        return workouts.first { $0.name == name } ?? workouts.first
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
                // Pinned tiles stand alone with no exercise heading around them, so each leads with
                // the exercise name and carries its metric name in the subtitle (`showsExerciseName`).
                switch tileType {
                case .weight:
                    ExerciseWeightTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true)
                case .repetitions:
                    ExerciseRepetitionsTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true)
                case .volume:
                    ExerciseVolumeTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true)
                case .setVolume:
                    ExerciseSetVolumeTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true)
                case .estimatedOneRepMax:
                    ExerciseE1RMTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true)
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
