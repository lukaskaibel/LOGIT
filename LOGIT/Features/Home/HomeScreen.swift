//
//  HomeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.09.21.
//

import ColorfulX
import CoreData
import SwiftUI
import WishKit

struct HomeScreen: View {
    // MARK: - AppStorage

    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3
    @AppStorage("pinnedMeasurements") private var pinnedMeasurementsData: Data = Data()
    @AppStorage("pinnedExercises") private var pinnedExercisesData: Data = Data()

    // MARK: - Environment

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @EnvironmentObject private var measurementController: MeasurementEntryController
    @EnvironmentObject private var database: Database

    // MARK: - State

    @State private var showNoWorkoutTip = false
    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingSettings = false
    @State private var isShowingWishkit = false
    @State private var isShowingMeasurementsEditSheet = false
    @State private var isShowingExercisesPinEditSheet = false

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
                            if showNoWorkoutTip {
                                noWorkoutTip
                                    .padding(.horizontal)
                            }
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

                            VStack(spacing: SECTION_HEADER_SPACING) {
                                Text(NSLocalizedString("thisWeek", comment: ""))
                                    .sectionHeaderStyle2()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(spacing: 8) {
                                    currentWeekWeeklyTargetWidget
                                    Button {
                                        homeNavigationCoordinator.path.append(.overallSets)
                                    } label: {
                                        OverallSetsTile(workouts: workouts)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(TileButtonStyle())
                                    Button {
                                        homeNavigationCoordinator.path.append(.volume)
                                    } label: {
                                        VolumeTile(workouts: workouts)
                                    }
                                    .buttonStyle(TileButtonStyle())
                                    Button {
                                        homeNavigationCoordinator.path.append(.muscleGroupsOverview)
                                    } label: {
                                        MuscleGroupSplitTile(workouts: workouts)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(TileButtonStyle())
                                }
                            }
                            .padding(.horizontal)

                            measurementsSection
                                .padding(.horizontal)

                            exercisesSection
                                .padding(.horizontal)

                            VStack {
                                Button {
                                    isShowingWishkit = true
                                } label: {
                                    Label(NSLocalizedString("whatsStillMissing", comment: ""), systemImage: "questionmark.bubble.fill")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                            .padding(.horizontal)
                            .padding(.top, 30)
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
                .onAppear {
                    showNoWorkoutTip = workouts.isEmpty
                }
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
                .sheet(isPresented: $isShowingWishkit) {
                    WishKit.FeedbackListView().withNavigation()
                        .onAppear {
                            WishKit.configure(with: WISHKIT_API_KEY)
                            WishKit.config.allowUndoVote = true
                            WishKit.theme.primaryColor = .accentColor
                            WishKit.config.buttons.saveButton.textColor = .setBoth(to: .black)
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
                        MuscleGroupSplitScreen()
                    case .overallSets: OverallSetsScreen(workouts: workouts)
                    case .targetPerWeek: TargetPerWeekDetailScreen()
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

    private var currentWeekWeeklyTargetWidget: some View {
        Button {
            homeNavigationCoordinator.path.append(.targetPerWeek)
        } label: {
            CurrentWeekWeeklyTargetTile()
        }
        .buttonStyle(TileButtonStyle())
    }

    private var noWorkoutTip: some View {
        TipView(
            title: NSLocalizedString("noWorkoutsTip", comment: ""),
            description: NSLocalizedString("noWorkoutsTipDescription", comment: ""),
            buttonAction: nil,
            isShown: $showNoWorkoutTip
        )
        .padding(CELL_PADDING)
        .tileStyle()
    }

    // MARK: - Measurements Section

    private var pinnedMeasurements: [MeasurementEntryType] {
        guard let decoded = try? JSONDecoder().decode([String].self, from: pinnedMeasurementsData) else {
            return [.bodyweight]
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
                Button {
                    isShowingMeasurementsEditSheet = true
                } label: {
                    Text(NSLocalizedString("edit", comment: ""))
                }
                .fontWeight(.semibold)
            }
            VStack(spacing: 8) {
                ForEach(pinnedMeasurements, id: \.rawValue) { measurementType in
                    Button {
                        homeNavigationCoordinator.path.append(.measurementDetail(measurementType))
                    } label: {
                        MeasurementTile(measurementType: measurementType)
                    }
                    .buttonStyle(TileButtonStyle())
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
                Text(NSLocalizedString("exercises", comment: ""))
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
                ForEach(pinnedExerciseTiles, id: \.id) { pinnedTile in
                    if let exercise = database.getExercise(byID: pinnedTile.exerciseID) {
                        pinnedExerciseTileView(for: exercise, tileType: pinnedTile.tileType)
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
                    PinnedExerciseWeightTile(exercise: exercise, workoutSets: workoutSets)
                case .repetitions:
                    PinnedExerciseRepetitionsTile(exercise: exercise, workoutSets: workoutSets)
                case .volume:
                    PinnedExerciseVolumeTile(exercise: exercise, workoutSets: workoutSets)
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
