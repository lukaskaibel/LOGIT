//
//  LOGITApp.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.21.
//

import SwiftUI
import Transmission

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
    /// Mirrors the drag phase of the recorder's interactive dismissal (see
    /// `WorkoutRecorderPresentationController`); feeds `\.workoutRecorderIsDragging`.
    @State private var recorderIsDragging = false
    /// True once the recorder's presentation slide-in has landed; feeds
    /// `\.workoutRecorderIsSettled`, which gates the persistent exercise tray sheet.
    @State private var recorderIsSettled = false
    /// Lets the recorder's header drive the interactive dismissal from inside the
    /// presented content (see `WorkoutRecorderDragDriver`).
    @State private var recorderDragDriver = WorkoutRecorderDragDriver()

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
        TestScenario.active?.prepareUserDefaults()

        let database: Database
        if ScreenshotFixtures.isEnabled {
            // Fastlane snapshot run: use the seeded in-memory preview store so
            // every captured screen shows the same curated, photogenic data.
            database = Database(isPreview: true)
        } else if let scenario = TestScenario.active {
            // Scenario launch (-SCENARIO empty|one|many): fresh in-memory
            // store seeded for one critical data state; the real store and
            // defaults stay untouched.
            database = Database(inMemory: true)
            scenario.seedAtLaunch(into: database)
        } else {
            database = Database()
        }

        let measurementController = MeasurementEntryController(database: database)
        TestScenario.active?.seedMeasurements(using: measurementController)

        let defaultExerciseService = DefaultExerciseService(database: database)
        let defaultTemplateService = DefaultTemplateService(database: database)
        if let scenario = TestScenario.active {
            // Scenario stores are ephemeral: import the default content and
            // seed synchronously so the very first frame already shows the
            // final state (the `.task` import would race the initial render).
            defaultExerciseService.loadDefaultExercisesIfNeeded()
            defaultTemplateService.loadDefaultTemplatesIfNeeded()
            scenario.seedAfterDefaultContentLoaded(database: database)
        }

        _database = StateObject(wrappedValue: database)
        _templateService = StateObject(wrappedValue: TemplateService(database: database))
        _measurementController = StateObject(wrappedValue: measurementController)
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
        _defaultExerciseService = StateObject(wrappedValue: defaultExerciseService)
        _defaultTemplateService = StateObject(wrappedValue: defaultTemplateService)
        _exerciseSuggestionService = StateObject(wrappedValue: ExerciseSuggestionService(database: database))

        UserDefaults.standard.register(defaults: [
            "weightUnit": WeightUnit.defaultFromLocale.rawValue,
            "distanceUnit": DistanceUnit.defaultFromLocale.rawValue,
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
                // Anchored on the TabView (stable for the app's lifetime) rather than
                // inside the accessory: TabView re-hosts the accessory content at
                // times, and a presentation anchored in it would be torn down
                // (auto-dismissed) with every re-host. The recorder slides up from the
                // bottom and is dragged back down to dismiss, via Transmission.
                .presentation(
                    transition: recorderTransition,
                    isPresented: $isShowingWorkoutRecorder
                ) {
                    workoutRecorderDestination
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
                .sheet(isPresented: $isShowingWelcome) {
                    FirstStartScreen()
                        .interactiveDismissDisabled()
                }
                .task {
                    if !setupDone {
                        isShowingWelcome = true
                    }
                    // Scenario launches already imported default content in init.
                    if TestScenario.active == nil {
                        defaultExerciseService.loadDefaultExercisesIfNeeded()
                        // Skipped for fastlane screenshot runs so the curated fixture data stays
                        // exactly what the marketing screenshots expect.
                        if !ScreenshotFixtures.isEnabled {
                            defaultTemplateService.loadDefaultTemplatesIfNeeded()
                        }
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
                    #if DEBUG
                    // Live Activity verification hook: deterministically start a rest timer so the
                    // running-chrono Dynamic Island (compact/minimal) can be reproduced from the CLI.
                    // Lives here (not in the recorder view) so it fires regardless of what is on screen.
                    if ProcessInfo.processInfo.arguments.contains("-UITEST_START_REST_TIMER"),
                       let restTimerSet = workoutRecorder.workout?.sets.first {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        workoutRecorder.activeRestTimerSet = restTimerSet
                        chronograph.mode = .timer
                        chronograph.setSeconds(90)
                        chronograph.start()
                    }
                    #endif
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
                // Persisting to disk failed even after the retry: without this, the data loss
                // would be silent — the UI keeps showing the in-memory objects until the app is
                // relaunched, and only then does the user find their workout gone.
                .alert(
                    NSLocalizedString("saveFailedTitle", comment: ""),
                    isPresented: $database.lastSaveFailed
                ) {
                    Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
                } message: {
                    Text(NSLocalizedString("saveFailedMessage", comment: ""))
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
                            // Make the whole pill tappable, not just the name/timer:
                            // the label's gaps and the maxWidth fill aren't hit-testable
                            // without an explicit content shape.
                            .contentShape(Rectangle())
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
                        .contentShape(Rectangle())
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

    /// The recorder screen as presented by Transmission. The presentation hosts it in
    /// its own `UIViewController`, so the environment is injected explicitly, exactly
    /// like the old overlay-based cover did.
    private var workoutRecorderDestination: some View {
        WorkoutRecorderScreen(chronograph: chronograph)
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
            .environment(\.workoutRecorderIsDragging, recorderIsDragging)
            .environment(\.workoutRecorderIsSettled, recorderIsSettled)
            .environment(\.workoutRecorderDragDriver, recorderDragDriver)
            // The old cover ignored the keyboard at container level; the recorder
            // manages keyboard overlap itself (scroll-to-focused-field + toolbar).
            .ignoresSafeArea(.keyboard)
    }

    private var recorderTransition: PresentationLinkTransition {
        .workoutRecorder(
            dragDriver: recorderDragDriver,
            onDragChanged: { dragging in
                if dragging {
                    // Tear the tray sheet down instantly: it must be gone before the
                    // pan gesture ends, or UIKit would forward the recorder's
                    // dismissal to it (see WorkoutRecorderPresentationController).
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        recorderIsDragging = true
                    }
                } else {
                    withAnimation {
                        recorderIsDragging = false
                    }
                }
            },
            onPresentationSettled: { completed in
                withAnimation {
                    recorderIsSettled = completed
                }
            },
            onDismissalEnded: { completed in
                // Transmission already flips `isShowingWorkoutRecorder` through its
                // presentation delegate; only the phase mirrors need resetting here.
                if completed {
                    recorderIsSettled = false
                    recorderIsDragging = false
                } else {
                    withAnimation {
                        recorderIsDragging = false
                    }
                }
            }
        )
    }

    private func showWorkoutRecorder() {
        recorderIsDragging = false
        recorderIsSettled = false
        withAnimation {
            isShowingWorkoutRecorder = true
        }
    }

    private func dismissWorkoutRecorder() {
        // Drop the tray sheet first, without animation: when a presented stack is
        // dismissed, UIKit only animates the topmost view controller — with the tray
        // still up, the recorder would vanish instead of morphing back into the pill.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            recorderIsSettled = false
        }
        DispatchQueue.main.async {
            withAnimation {
                isShowingWorkoutRecorder = false
            }
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
