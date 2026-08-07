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

    @AppStorage("pinnedMeasurements") private var pinnedMeasurementsData: Data = Data()
    @AppStorage("pinnedExercises") private var pinnedExercisesData: Data = Data()
    /// The Summary's one timeframe, persisted so the screen comes back the way it was left — see
    /// `TrendWindow`. Stored as the raw string because `@AppStorage` can't hold the enum directly;
    /// `TrendWindow.stored` is the only place it's decoded.
    @AppStorage("summaryTrendWindow") private var summaryTrendWindowRaw: String = TrendWindow.default.rawValue

    // MARK: - Environment

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @EnvironmentObject private var database: Database

    // MARK: - State

    @StateObject private var summaryViewModel = SummaryViewModel()

    @State private var isShowingMeasurementsEditSheet = false
    @State private var isShowingExercisesPinEditSheet = false
    @State private var isShowingMeasurementsTip = true
    @State private var isShowingExercisesTip = true
    @State private var isShowingStartWorkoutSheet = false
    @State private var isShowingWorkoutGoalSheet = false
    @State private var didApplyScreenshotDeepLink = false

    // MARK: - Body

    /// The screen's selected timeframe, read from and written back to `summaryTrendWindowRaw`.
    private var trendWindow: Binding<TrendWindow> {
        Binding(
            get: { TrendWindow.stored(summaryTrendWindowRaw) },
            set: { summaryTrendWindowRaw = $0.rawValue }
        )
    }

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { workouts in
            NavigationStack(path: $homeNavigationCoordinator.path) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            summaryHeader(workouts: workouts)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            VStack(spacing: SECTION_SPACING) {
                                if summaryViewModel.mode(workouts: workouts) == .firstOpen {
                                    SummaryWelcomeView(
                                        onStartWorkout: { isShowingStartWorkoutSheet = true },
                                        onBrowseTemplates: { homeNavigationCoordinator.path.append(.templateList) }
                                    )
                                } else {
                                    summaryContent(workouts: workouts)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
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
                    // The title row is in-flow scroll content, so the navigation bar stays hidden here
                    // (it must not leak into pushed screens — see ScenarioScreenshots). A soft top edge
                    // effect keeps the ColorfulX wash reaching the very top instead of being cut off.
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .toolbar(.hidden, for: .navigationBar)
                    .sheet(isPresented: $isShowingStartWorkoutSheet) {
                        WorkoutStartSheet()
                    }
                    .sheet(isPresented: $isShowingWorkoutGoalSheet) {
                        NavigationStack {
                            ChangeWeeklyWorkoutGoalScreen()
                        }
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
                            MuscleGroupsOverviewScreen(initialWindow: trendWindow.wrappedValue)
                        case .muscleTargetSplit:
                            MuscleTargetSplitScreen()
                        case let .muscleGroupDetail(group, initialWindow):
                            MuscleGroupDetailScreen(muscleGroup: group, initialWindow: initialWindow)
                        case let .summaryStat(metric, window):
                            SummaryStatScreen(
                                metric: metric,
                                workouts: workouts,
                                initialWindow: window ?? trendWindow.wrappedValue
                            )
                        case .progressHighlights:
                            ProgressHighlightsScreen(workouts: workouts)
                        case .strength:
                            StrengthScreen(workouts: workouts, initialWindow: trendWindow.wrappedValue)
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
                    .onAppear {
                        applyScreenshotDeepLinkIfNeeded(workouts: workouts)
                    }
                    .task {
                        // Screenshot-only, deterministic scroll for the marketing capture: once the
                        // screen has laid out and seeded its pins, jump to a fixed anchor so the pinned
                        // tiles clear the Start Workout bar. The UI test can't do this — its gesture
                        // flick travels an unpredictable, per-run distance — so the app positions it
                        // instead. No-op for real users (guarded on the fixtures + deep-link flags).
                        guard ScreenshotFixtures.isEnabled,
                              ScreenshotFixtures.deepLinkTarget == "progress" else { return }
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        proxy.scrollTo("screenshotPinnedAnchor", anchor: UnitPoint(x: 0.5, y: 0.57))
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Sections

    /// The large-title row: "Summary" and the weekly-goal pill on one line, at the very top of the
    /// scroll. Rendered in-flow rather than as a navigation-bar title for two reasons. It sits where
    /// iOS 26's own apps put a large title — hard against the top inset — instead of below the empty
    /// 44 pt bar row a stock large title reserves for toolbar items; and custom `.largeTitle`-placement
    /// toolbar content is not exposed to the accessibility tree on iOS 26 (the bar reports zero
    /// children), so a toolbar pill could never be reached by VoiceOver or UI automation. In-flow
    /// content is fully accessible and costs only that the pill scrolls away with the title.
    private func summaryHeader(workouts: [Workout]) -> some View {
        HStack {
            Text(NSLocalizedString("summary", comment: ""))
                .font(.largeTitle.bold())
            Spacer()
            WeeklyGoalCountPill(
                workouts: workouts,
                onOpen: { homeNavigationCoordinator.path.append(.weeklyGoal) },
                onSetGoal: { isShowingWorkoutGoalSheet = true }
            )
        }
    }

    /// The merged Summary, in bands: the timeframe, then the trend, then the raw numbers, then the
    /// things the user chose to watch, and last what just happened.
    ///
    /// The picker comes first because everything under it is scoped by it — Strength and Balance, the
    /// four core stats, and the pinned exercise tiles all report over the one window it names. Before
    /// it existed the screen reported over five different spans at once and said so nowhere, which
    /// made the tiles quietly incomparable: a month-scoped Volume tile on the 3rd sat beside a
    /// four-week Strength tile.
    ///
    /// Strength and Balance lead the content because both halves always render and barely move
    /// window to window, so they anchor the screen; they answer "how am I moving" and "am I covering
    /// everything" in one glance before the raw numbers arrive. Highlights closes it — see
    /// `SummaryHighlightsSection` for why it is both last and unscoped.
    @ViewBuilder
    private func summaryContent(workouts: [Workout]) -> some View {
        TrendWindowPicker(selection: trendWindow)

        // The pair and the 2×2 grid are one block of six tiles reading one window, so they share the
        // grid's own spacing rather than the section gap — a `SECTION_SPACING` break between them
        // read as a boundary between two things, which is exactly what the picker just removed.
        VStack(spacing: SummaryStatTileGrid.tileSpacing) {
            SummaryTrendPair(workouts: workouts, window: trendWindow.wrappedValue)

            SummaryStatTileGrid(
                viewModel: summaryViewModel,
                workouts: workouts,
                window: trendWindow.wrappedValue,
                onOpenDetail: { metric in
                    homeNavigationCoordinator.path.append(.summaryStat(metric, nil))
                }
            )
        }

        // Fixed scroll anchor for the marketing screenshot (see the `.task` above).
        Color.clear
            .frame(height: 1)
            .id("screenshotPinnedAnchor")

        exercisesSection
        measurementsSection
        SummaryHighlightsSection(workouts: workouts)
    }

    // MARK: - Marketing screenshot deep links

    /// Opens the screen named by `-UITEST_DEEPLINK` once the summary has data.
    /// Detail targets push onto the nav path; `progress` is already handled by
    /// the pinned section's scroll anchor. Gated on `ScreenshotFixtures.isEnabled`
    /// so this can never run for a real user (App Store builds can't be handed
    /// launch arguments anyway).
    private func applyScreenshotDeepLinkIfNeeded(workouts: [Workout]) {
        guard ScreenshotFixtures.isEnabled,
              !didApplyScreenshotDeepLink,
              let target = ScreenshotFixtures.deepLinkTarget else { return }
        didApplyScreenshotDeepLink = true
        switch target {
        case "progress":
            // Pin a few seeded lifts so the capture shows real, climbing tiles
            // instead of the empty-state teaser; the scroll anchor does the framing.
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
        case "bodyWeight":
            homeNavigationCoordinator.path = [.measurementDetail(.bodyweight)]
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
                            pinnedExerciseTileView(
                                for: exercise,
                                tileType: pinnedTile.tileType,
                                window: trendWindow.wrappedValue
                            )
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
    
    /// A pinned tile, scoped to the screen's selected window like everything else under the picker.
    ///
    /// These tiles can follow the picker where the exercise detail screen's cannot: pinned, they lead
    /// with the exercise name and carry the metric in the subtitle (`showsExerciseName`), so they
    /// never print the words "current best" — the app-wide term for the four-week window that the
    /// recorder badges, the workout detail and the exercise screen all share. Widening the value here
    /// re-scopes a number; widening it there would redefine a term.
    @ViewBuilder
    private func pinnedExerciseTileView(
        for exercise: Exercise,
        tileType: ExerciseTileType,
        window: TrendWindow
    ) -> some View {
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
                    ExerciseWeightTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true, window: window)
                case .repetitions:
                    ExerciseRepetitionsTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true, window: window)
                case .volume:
                    ExerciseVolumeTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true, window: window)
                case .setVolume:
                    ExerciseSetVolumeTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true, window: window)
                case .estimatedOneRepMax:
                    ExerciseE1RMTile(exercise: exercise, workoutSets: workoutSets, showsExerciseName: true, window: window)
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
