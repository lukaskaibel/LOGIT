//
//  LOGITApp.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.21.
//

import SwiftUI

@main
struct LOGIT: App {
    enum TabType: Hashable {
        case home, templates, startWorkout, exercises, settings
    }

    // MARK: - AppStorage

    @AppStorage("setupDone") var setupDone: Bool = false

    // MARK: - State

    @StateObject private var database: Database
    @StateObject private var templateService: TemplateService
    @StateObject private var measurementController: MeasurementEntryController
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var muscleTargetSplitStore = MuscleTargetSplitStore()
    @StateObject private var workoutRecorder: WorkoutRecorder
    @StateObject private var workoutLiveActivityManager: WorkoutLiveActivityManager
    @StateObject private var muscleGroupService: MuscleGroupService
    @StateObject private var homeNavigationCoordinator = HomeNavigationCoordinator()
    @StateObject private var chronograph: Chronograph
    @StateObject private var defaultExerciseService: DefaultExerciseService
    @StateObject private var defaultTemplateService: DefaultTemplateService
    @StateObject private var exerciseSuggestionService: ExerciseSuggestionService

    @State private var selectedTab: TabType = .home
    @State private var isShowingWelcome = false
    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingStartWorkoutSheet = false
    @State private var isShowingLiveActivityShowcase = false

    // Import handling state
    @State private var importedWorkout: Workout?
    @State private var importedTemplate: Template?
    @State private var showingImportError = false
    @State private var importErrorMessage = ""

    // MARK: - Init

    init() {
        ScreenshotFixtures.prepareUserDefaultsIfNeeded()
        #if DEBUG
        DemoWorkoutSeeder.prepareUserDefaultsIfNeeded()
        #endif

        let database: Database
        if ScreenshotFixtures.isEnabled {
            // Fastlane snapshot run: use the seeded in-memory preview store so
            // every captured screen shows the same curated, photogenic data.
            database = Database(isPreview: true)
        } else {
            database = Database()
        }

        _database = StateObject(wrappedValue: database)
        _templateService = StateObject(wrappedValue: TemplateService(database: database))
        _measurementController = StateObject(wrappedValue: MeasurementEntryController(database: database))
        let workoutRecorder = WorkoutRecorder(database: database)
        _workoutRecorder = StateObject(wrappedValue: workoutRecorder)
        let chronograph = Chronograph()
        _chronograph = StateObject(wrappedValue: chronograph)
        _workoutLiveActivityManager = StateObject(
            wrappedValue: WorkoutLiveActivityManager(
                workoutRecorder: workoutRecorder,
                database: database,
                chronograph: chronograph
            )
        )
        _muscleGroupService = StateObject(wrappedValue: MuscleGroupService())
        _homeNavigationCoordinator = StateObject(wrappedValue: HomeNavigationCoordinator())
        _defaultExerciseService = StateObject(wrappedValue: DefaultExerciseService(database: database))
        _defaultTemplateService = StateObject(wrappedValue: DefaultTemplateService(database: database))
        _exerciseSuggestionService = StateObject(wrappedValue: ExerciseSuggestionService(database: database))

        UserDefaults.standard.register(defaults: [
            "weightUnit": WeightUnit.defaultFromLocale.rawValue,
            "workoutPerWeekTarget": -1,
            "setupDone": false,
        ])
        // Fixes issue with wrong Accent Color in Alerts
        UIView.appearance().tintColor = UIColor(named: "AccentColor")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            TabView {
                    Tab("summary", systemImage: "square.grid.2x2.fill") {
                        HomeScreen()
        //                #if targetEnvironment(simulator)
        //                    .statusBarHidden(true)
        //                #endif
                    }
                    Tab(NSLocalizedString("history", comment: ""), systemImage: "clock.fill") {
                        NavigationStack {
                            WorkoutListScreen()
                        }
                    }
                    Tab(NSLocalizedString("templates", comment: ""), systemImage: "list.bullet.rectangle.portrait.fill") {
                        NavigationStack {
                            TemplateListScreen()
                        }
                    }
                    Tab(NSLocalizedString("search", comment: ""), systemImage: "magnifyingglass", role: .search) {
                        GlobalSearchScreen()
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    startAndCurrentWorkoutButton
                        .frame(maxWidth: .infinity)
                }
                .environment(\.managedObjectContext, database.context)
                .environmentObject(database)
                .environmentObject(measurementController)
                .environmentObject(templateService)
                .environmentObject(purchaseManager)
                .environmentObject(networkMonitor)
                .environmentObject(workoutRecorder)
                .environmentObject(muscleGroupService)
                .environmentObject(muscleTargetSplitStore)
                .environmentObject(homeNavigationCoordinator)
                .environmentObject(chronograph)
                .environmentObject(exerciseSuggestionService)
                .environment(\.goHome) { selectedTab = .home }
                .environment(\.presentWorkoutRecorder, showWorkoutRecorder)
                .fullScreenDraggableCover(isPresented: $isShowingWorkoutRecorder) {
                    WorkoutRecorderScreen()
                        .environmentObject(database)
                        .environmentObject(measurementController)
                        .environmentObject(templateService)
                        .environmentObject(purchaseManager)
                        .environmentObject(networkMonitor)
                        .environmentObject(workoutRecorder)
                        .environmentObject(muscleGroupService)
                        .environmentObject(muscleTargetSplitStore)
                        .environmentObject(homeNavigationCoordinator)
                        .environmentObject(chronograph)
                        .environmentObject(exerciseSuggestionService)
                        .environment(\.managedObjectContext, database.context)
                        .environment(\.goHome) { selectedTab = .home }
                        .environment(\.dismissWorkoutRecorder) { dismissWorkoutRecorder() }
                }
//                    .presentation(transition: .slide, isPresented: $isShowingWorkoutRecorder) {
//                        TransitionReader { _ in
//                        }
//                    }
                .sheet(isPresented: $isShowingWelcome) {
                    FirstStartScreen()
                        .interactiveDismissDisabled()
                }
                .task {
                    if !setupDone {
                        isShowingWelcome = true
                    }
                    defaultExerciseService.loadDefaultExercisesIfNeeded()
                    // Skipped for fastlane screenshot runs so the curated fixture data stays
                    // exactly what the marketing screenshots expect.
                    if !ScreenshotFixtures.isEnabled {
                        defaultTemplateService.loadDefaultTemplatesIfNeeded()
                    }
                    #if DEBUG
                    DemoWorkoutSeeder.seedIfRequested(database: database)
                    #endif
                    Task {
                        do {
                            try await purchaseManager.loadProducts()
                        } catch {
                            print(error)
                        }
                    }
                    // Fastlane screenshot trigger: open the recorder cover
                    // automatically once the tab view is on-screen so the
                    // WorkoutRecorder screenshot test doesn't have to chase
                    // the tabViewBottomAccessory pill (which swallows
                    // synthetic taps on iOS 26).
                    if ScreenshotFixtures.shouldAutoPresentRecorder,
                       workoutRecorder.workout != nil {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        showWorkoutRecorder()
                    }
                    // Fastlane screenshot trigger for the Live Activity
                    // marketing view. Swaps the whole screen for a
                    // Lock Screen-style composition of two Live Activity
                    // cards (auto rest timer + current set).
                    if ScreenshotFixtures.shouldShowLiveActivityShowcase {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        isShowingLiveActivityShowcase = true
                    }
                }
                .fullScreenCover(isPresented: $isShowingLiveActivityShowcase) {
                    LiveActivityShowcaseView()
                }
                .preferredColorScheme(.dark)
                .onAppear {
                    // Fixes issue with Alerts and Confirmation Dialogs not in dark mode
                    let scenes = UIApplication.shared.connectedScenes
                    guard let scene = scenes.first as? UIWindowScene else { return }
                    scene.keyWindow?.overrideUserInterfaceStyle = .dark
                }
                .onOpenURL { url in
                    handleIncomingFile(url: url)
                }
                .sheet(item: $importedWorkout) { workout in
                    NavigationStack {
                        WorkoutEditorScreen(
                            workout: workout,
                            isAddingNewWorkout: false,
                            isImportedWorkout: true
                        )
                    }
                    .environmentObject(database)
                    .environmentObject(measurementController)
                    .environmentObject(templateService)
                    .environmentObject(purchaseManager)
                    .environmentObject(networkMonitor)
                    .environmentObject(workoutRecorder)
                    .environmentObject(muscleGroupService)
                    .environmentObject(muscleTargetSplitStore)
                    .environmentObject(homeNavigationCoordinator)
                    .environmentObject(chronograph)
                    .environmentObject(exerciseSuggestionService)
                    .interactiveDismissDisabled()
                    .onDisappear {
                        // Clean up if dismissed without saving
                        if database.isTemporaryObject(workout) {
                            database.deleteAllTemporaryObjects()
                        }
                    }
                }
                .fullScreenCover(item: $importedTemplate) { template in
                    TemplateEditorScreen(
                        template: template,
                        isEditingExistingTemplate: false,
                        isImportedTemplate: true
                    )
                    .environmentObject(database)
                    .environmentObject(measurementController)
                    .environmentObject(templateService)
                    .environmentObject(purchaseManager)
                    .environmentObject(networkMonitor)
                    .environmentObject(workoutRecorder)
                    .environmentObject(muscleGroupService)
                    .environmentObject(muscleTargetSplitStore)
                    .environmentObject(homeNavigationCoordinator)
                    .environmentObject(chronograph)
                    .environmentObject(exerciseSuggestionService)
                    .presentationBackground(Color.black)
                    .onDisappear {
                        // Clean up if dismissed without saving
                        if database.isTemporaryObject(template) {
                            database.deleteAllTemporaryObjects()
                        }
                    }
                }
                .alert(
                    NSLocalizedString("importError", comment: ""),
                    isPresented: $showingImportError
                ) {
                    Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
                } message: {
                    Text(importErrorMessage)
                }
        }
    }

    // MARK: - Methods / Computed Properties

    func testLanguage() {
        UserDefaults.standard.set(["eng"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    func testFirstStart() {
        UserDefaults.standard.set(false, forKey: "setupDone")
    }

    private var startAndCurrentWorkoutButton: some View {
        if #available(iOS 26.0, *) {
            if let workout = workoutRecorder.workout {
                AnyView(
                    Button {
                        showWorkoutRecorder()
                    } label: {
                        CurrentWorkoutView(workoutName: workout.name, workoutDate: workout.date)
                            .frame(maxWidth: .infinity)
    //                        .background(.regularMaterial)
    //                        .clipShape(RoundedRectangle(cornerRadius: 15))
    //                        .shadow(radius: 10)
    //                        .padding(.horizontal, 12)
    //                        .padding(.bottom, 5)
                    }
                    .buttonStyle(TileButtonStyle())
                    .gesture(
                        DragGesture()
                            .onChanged { dragValue in
                                if dragValue.translation.height < 0 {
                                    showWorkoutRecorder()
                                }
                            }
                    )
                )
            } else {
                AnyView(
                    Button {
                        isShowingStartWorkoutSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text(NSLocalizedString("startWorkout", comment: ""))
                        }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                    }
                    .tint(Color.label)
                    .sheet(isPresented: $isShowingStartWorkoutSheet) {
                        WorkoutStartSheet()
                    }
                )
            }
        } else {
            AnyView(
                ZStack {
                    Rectangle()
                        .fill(.bar)
                        .frame(height: 140)
                        .mask {
                            VStack(spacing: 0) {
                                LinearGradient(colors: [Color.black.opacity(0),
                                                        Color.black],
                                               startPoint: .top,
                                               endPoint: .bottom)
                                    .frame(height: 45)

                                Rectangle()
                            }
                        }
                    if let workout = workoutRecorder.workout {
                        Button {
                            showWorkoutRecorder()
                        } label: {
                            CurrentWorkoutView(workoutName: workout.name, workoutDate: workout.date)
                                .frame(maxWidth: .infinity)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                                .shadow(radius: 10)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 5)
                        }
                        .buttonStyle(TileButtonStyle())
                        .gesture(
                            DragGesture()
                                .onChanged { dragValue in
                                    if dragValue.translation.height < 0 {
                                        showWorkoutRecorder()
                                    }
                                }
                        )
                        .transition(.move(edge: .bottom))
                    } else {
                        Button {
                            isShowingStartWorkoutSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text(NSLocalizedString("startWorkout", comment: ""))
                            }
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .shadow(radius: 10)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 5)
                        }
                        .tint(Color.label)
                        .sheet(isPresented: $isShowingStartWorkoutSheet) {
                            WorkoutStartSheet()
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .edgesIgnoringSafeArea(.bottom)
            )
        }
    }

    private func showWorkoutRecorder() {
        withAnimation {
            isShowingWorkoutRecorder = true
        }
    }

    private func dismissWorkoutRecorder() {
        withAnimation {
            isShowingWorkoutRecorder = false
        }
    }
    
    private func handleIncomingFile(url: URL) {
        let fileExtension = url.pathExtension.lowercased()

        DispatchQueue.global(qos: .userInitiated).async {
            let sharingService = WorkoutSharingService(database: database)

            var importedWorkoutResult: Workout?
            var importedTemplateResult: Template?
            var errorMessage: String?
            var hasError = false

            switch fileExtension {
            case "logitworkout":
                do {
                    let workout = try sharingService.importWorkout(from: url)
                    importedWorkoutResult = workout
                } catch {
                    errorMessage = error.localizedDescription
                    hasError = true
                }
            case "logittemplate":
                do {
                    let template = try sharingService.importTemplate(from: url)
                    importedTemplateResult = template
                } catch {
                    errorMessage = error.localizedDescription
                    hasError = true
                }
            default:
                errorMessage = NSLocalizedString("unsupportedFileType", comment: "")
                hasError = true
            }

            DispatchQueue.main.async {
                if let workout = importedWorkoutResult {
                    self.importedWorkout = workout
                }

                if let template = importedTemplateResult {
                    self.importedTemplate = template
                }

                if hasError, let message = errorMessage {
                    self.importErrorMessage = message
                    self.showingImportError = true
                }
            }
        }
    }
}

// MARK: - EnvironmentValues/Keys

struct GoHomeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

struct PresentWorkoutRecorderKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

struct DismissWorkoutRecorderKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var goHome: () -> Void {
        get { self[GoHomeKey.self] }
        set { self[GoHomeKey.self] = newValue }
    }

    var presentWorkoutRecorder: () -> Void {
        get { self[PresentWorkoutRecorderKey.self] }
        set { self[PresentWorkoutRecorderKey.self] = newValue }
    }

    var dismissWorkoutRecorder: () -> Void {
        get { self[DismissWorkoutRecorderKey.self] }
        set { self[DismissWorkoutRecorderKey.self] = newValue }
    }
}
