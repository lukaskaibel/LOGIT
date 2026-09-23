//
//  LOGITApp.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.21.
//

import SwiftUI
import TipKit
import Transmission

@main
struct LOGIT: App {
    enum TabType: Hashable {
        case home, templates, startWorkout, exercises, settings
    }

    // MARK: - AppStorage

    @AppStorage("setupDone") var setupDone: Bool = false

    // MARK: - State

    // Held, not observed: this body only hands the objects down, and every view that shows their
    // data observes them itself. As `@StateObject`s, any publish re-ran the whole body (a Cancel's
    // rollback, a rest running out, a StoreKit response), and the TabView pushed its items to
    // UIKit again. A push while a sheet, a confirmation dialog or a popover has the tab bar's tint
    // dimmed left the unselected tabs in the accent colour after it closed. The same goes for the
    // scene phase, which is why the body doesn't read it either. What the scene does react to
    // lives in views of its own below: `StartOrCurrentWorkoutButton` (the recorder),
    // `SaveFailedAlert` (the database) and `ImportBodyWeightOnForeground` (the scene phase).
    @State private var database: Database
    @State private var templateService: TemplateService
    @State private var measurementController: MeasurementEntryController
    @State private var purchaseManager = PurchaseManager()
    @State private var networkMonitor = NetworkMonitor()
    @State private var muscleFocusStore = MuscleFocusStore()
    @State private var workoutRecorder: WorkoutRecorder
    @State private var workoutLiveActivityManager: WorkoutLiveActivityManager
    @State private var muscleGroupService: MuscleGroupService
    @State private var homeNavigationCoordinator = HomeNavigationCoordinator()
    @State private var chronograph: Chronograph
    @State private var defaultExerciseService: DefaultExerciseService
    @State private var defaultTemplateService: DefaultTemplateService
    @State private var exerciseSuggestionService: ExerciseSuggestionService
    @State private var healthKitSyncManager: HealthKitSyncManager
    @State private var bodyMeasurementSyncManager: BodyMeasurementSyncManager

    @State private var selectedTab: TabType = .home
    @State private var isShowingWelcome = false
    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingStartWorkoutSheet = false
    @State private var isShowingLiveActivityShowcase = false
    /// True once the recorder's presentation slide-in has landed; feeds
    /// `\.workoutRecorderIsSettled`, which gates the persistent exercise tray sheet.
    @State private var recorderIsSettled = false
    /// Lets the recorder's list and header drag the presented recorder from inside its
    /// content (see `WorkoutRecorderDragDriver`).
    @State private var recorderDragDriver = WorkoutRecorderDragDriver()

    // Import handling state
    @State private var importedWorkout: Workout?
    @State private var importedTemplate: Template?
    @State private var showingImportError = false
    @State private var importErrorMessage = ""

    // MARK: - Tips

    /// TipKit, set up before any view reads a tip. Scenario and marketing-screenshot launches start
    /// from a clean datastore so every run shows the same thing, and hide tips unless a test passes
    /// `-UITEST_SHOW_TIPS`: an inline tip shifts the Summary, which the standing screenshot suites and
    /// the App Store captures navigate by.
    private static func configureTips() {
        let args = ProcessInfo.processInfo.arguments
        if TestScenario.active != nil || ScreenshotFixtures.isEnabled {
            try? Tips.resetDatastore()
            if !args.contains("-UITEST_SHOW_TIPS") {
                Tips.hideAllTipsForTesting()
            }
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    // MARK: - Init

    init() {
        ScreenshotFixtures.prepareUserDefaultsIfNeeded()
        #if DEBUG
        DemoWorkoutSeeder.prepareUserDefaultsIfNeeded()
        #endif
        TestScenario.active?.prepareUserDefaults()
        // Before any view reads the switch: folds the two retired mode-scoped auto-rest
        // switches into the single one.
        AutoRestSettings.migrateLegacySwitchesIfNeeded()
        Self.configureTips()

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

        let bodyMeasurementSyncManager = BodyMeasurementSyncManager(database: database)
        _bodyMeasurementSyncManager = State(initialValue: bodyMeasurementSyncManager)
        let measurementController = MeasurementEntryController(
            database: database, bodyMeasurementSync: bodyMeasurementSyncManager
        )
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

        _database = State(initialValue: database)
        _templateService = State(initialValue: TemplateService(database: database))
        _measurementController = State(initialValue: measurementController)
        let healthKitSyncManager = HealthKitSyncManager()
        _healthKitSyncManager = State(initialValue: healthKitSyncManager)
        let workoutRecorder = WorkoutRecorder(database: database, healthKitSync: healthKitSyncManager)
        _workoutRecorder = State(initialValue: workoutRecorder)
        let chronograph = Chronograph()
        _chronograph = State(initialValue: chronograph)
        _workoutLiveActivityManager = State(
            initialValue: WorkoutLiveActivityManager(
                workoutRecorder: workoutRecorder,
                database: database,
                chronograph: chronograph
            )
        )
        _muscleGroupService = State(initialValue: MuscleGroupService())
        _defaultExerciseService = State(initialValue: defaultExerciseService)
        _defaultTemplateService = State(initialValue: defaultTemplateService)
        _exerciseSuggestionService = State(initialValue: ExerciseSuggestionService(database: database))

        UserDefaults.standard.register(defaults: [
            "weightUnit": WeightUnit.defaultFromLocale.rawValue,
            "distanceUnit": DistanceUnit.defaultFromLocale.rawValue,
            "workoutPerWeekTarget": -1,
            "setupDone": false,
            CalorieEstimator.enabledKey: true,
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
                    // Settings spends the last regular tab slot. It used to be a sheet behind the
                    // Summary's profile avatar; that avatar had nowhere to live once the Summary's
                    // title row became a scrolling one shared with the weekly-goal pill.
                    Tab(NSLocalizedString("settings", comment: ""), systemImage: "gearshape.fill") {
                        NavigationStack {
                            SettingsScreen()
                        }
                    }
                    .accessibilityIdentifier("settingsButton")
                    Tab(NSLocalizedString("search", comment: ""), systemImage: "magnifyingglass", role: .search) {
                        GlobalSearchScreen()
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    StartOrCurrentWorkoutButton(
                        isShowingStartWorkoutSheet: $isShowingStartWorkoutSheet,
                        showWorkoutRecorder: showWorkoutRecorder
                    )
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
                .environmentObject(muscleFocusStore)
                .environmentObject(homeNavigationCoordinator)
                .environmentObject(chronograph)
                .environmentObject(exerciseSuggestionService)
                .environmentObject(healthKitSyncManager)
                .environmentObject(bodyMeasurementSyncManager)
                .environment(\.goHome) { selectedTab = .home }
                .environment(\.presentWorkoutRecorder, showWorkoutRecorder)
                .sheet(isPresented: $isShowingWelcome) {
                    FirstStartScreen()
                        .interactiveDismissDisabled()
                }
                .modifier(ImportBodyWeightOnForeground(
                    bodyMeasurementSyncManager: bodyMeasurementSyncManager,
                    isEnabled: shouldImportBodyWeight
                ))
                .task {
                    if !setupDone {
                        isShowingWelcome = true
                    }
                    if shouldImportBodyWeight {
                        // Before the import: a body-fat grant made here is what lets it read body fat.
                        await HealthAuthorizationRefresh.requestMissingAuthorization(
                            workouts: healthKitSyncManager,
                            bodyMeasurements: bodyMeasurementSyncManager
                        )
                        await bodyMeasurementSyncManager.importFromHealth()
                    }
                    // Scenario launches already imported default content in init.
                    if TestScenario.active == nil {
                        // On a fresh install of an account that has used LOGIT before, the
                        // library is already in iCloud: seeding ahead of the first import would
                        // add a second copy of every built-in exercise and template. The welcome
                        // sheet covers the wait; a slow import only costs a later merge.
                        if defaultExerciseService.hasNeverLoadedLibrary {
                            await database.waitForInitialCloudKitImport(timeout: .seconds(20))
                        }
                        defaultExerciseService.loadDefaultExercisesIfNeeded()
                        // Skipped for fastlane screenshot runs so the curated fixture data stays
                        // exactly what the marketing screenshots expect.
                        if !ScreenshotFixtures.isEnabled {
                            defaultTemplateService.loadDefaultTemplatesIfNeeded()
                        }
                    }
                    #if DEBUG
                    DemoWorkoutSeeder.seedIfRequested(database: database)
                    DemoWorkoutSeeder.seedHighlightsDemoIfRequested(database: database)
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
                    // UI-test hook: boot straight into a brand-new EMPTY workout so the header's
                    // auto-expanded start state is reachable without driving the start-workout UI
                    // (the accessory pill swallows synthetic taps on iOS 26).
                    if ProcessInfo.processInfo.arguments.contains("-UITEST_START_EMPTY_WORKOUT"),
                       workoutRecorder.workout == nil {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        workoutRecorder.startWorkout()
                        showWorkoutRecorder()
                    }
                    // UI-test hook: a fresh workout with one logged set — with `-SCENARIO empty`, a
                    // brand-new user's first finish (no goal, no history to beat). Typing the set
                    // in from a test doesn't work: the tray is its own presentation, so the field
                    // behind it never reads as focused to XCUITest.
                    if ProcessInfo.processInfo.arguments.contains("-UITEST_START_LOGGED_WORKOUT"),
                       workoutRecorder.workout == nil,
                       let exercise = database.getExercises(for: .chest).first {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        workoutRecorder.startWorkout()
                        workoutRecorder.addSetGroup(with: exercise)
                        if let set = workoutRecorder.workout?.setGroups.first?.sets.first as? StandardSet,
                           let entry = set.entries.first {
                            entry.repetitions = 10
                            entry.weight = 60000
                        }
                        showWorkoutRecorder()
                    }
                    // UI-test hook: the finish panel's highlights, every shape at once — two weight
                    // records, a repetitions record, a Strength improvement, a repetitions
                    // improvement and a weight improvement, against the history seeded above.
                    if DemoWorkoutSeeder.isHighlightsDemoRequested, workoutRecorder.workout == nil {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        workoutRecorder.startWorkout()
                        workoutRecorder.workout?.name = "Push Day"
                        for demoEntry in DemoWorkoutSeeder.highlightsDemoPlan(database: database) {
                            workoutRecorder.addSetGroup(with: demoEntry.exercise)
                            if let set = workoutRecorder.workout?.setGroups.last?.sets.first as? StandardSet,
                               let entry = set.entries.first {
                                entry.repetitions = Int64(demoEntry.today.reps)
                                entry.weight = Int64(demoEntry.today.grams)
                            }
                        }
                        showWorkoutRecorder()
                    }
                    #endif
                    #if DEBUG
                    // Release hook: materialize the whole model in the CloudKit *development*
                    // schema so every field of a new model version shows up in the console and
                    // can be deployed to production. Needs an iCloud account on the device;
                    // prints the resulting record types to the console.
                    if ProcessInfo.processInfo.arguments.contains("-INITIALIZE_CLOUDKIT_SCHEMA") {
                        print("LOGIT: initializing CloudKit development schema…")
                        let initialized = database.initializeCloudKitDevelopmentSchema()
                        print("LOGIT: CloudKit schema initialization \(initialized ? "SUCCEEDED" : "FAILED")")
                    }
                    #endif
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
                    .environmentObject(muscleFocusStore)
                    .environmentObject(homeNavigationCoordinator)
                    .environmentObject(chronograph)
                    .environmentObject(exerciseSuggestionService)
                    .environmentObject(healthKitSyncManager)
                    .environmentObject(bodyMeasurementSyncManager)
                    .interactiveDismissDisabled()
                    .onDisappear {
                        // Clean up if dismissed without saving
                        if database.isTemporaryObject(workout) {
                            database.deleteAllTemporaryObjects()
                        }
                    }
                }
                .sheet(item: $importedTemplate) { template in
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
                    .environmentObject(muscleFocusStore)
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
                .modifier(SaveFailedAlert(database: database))
        }
    }

    // MARK: - Methods / Computed Properties

    /// Scenario launches use a throwaway store and must stay deterministic, so the Health
    /// import is off for them — except when a UI test explicitly asks to exercise it.
    private var shouldImportBodyWeight: Bool {
        if TestScenario.active == nil { return true }
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITEST_BODYWEIGHT_SYNC")
        #else
        return false
        #endif
    }

    func testLanguage() {
        UserDefaults.standard.set(["eng"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    func testFirstStart() {
        UserDefaults.standard.set(false, forKey: "setupDone")
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
            .environmentObject(muscleFocusStore)
            .environmentObject(homeNavigationCoordinator)
            .environmentObject(chronograph)
            .environmentObject(exerciseSuggestionService)
            .environmentObject(healthKitSyncManager)
            .environmentObject(bodyMeasurementSyncManager)
            .environment(\.managedObjectContext, database.context)
            .environment(\.goHome) { selectedTab = .home }
            .environment(\.dismissWorkoutRecorder) { dismissWorkoutRecorder() }
            .environment(\.workoutRecorderIsSettled, recorderIsSettled)
            .environment(\.workoutRecorderDragDriver, recorderDragDriver)
            // The old cover ignored the keyboard at container level; the recorder
            // manages keyboard overlap itself (scroll-to-focused-field + toolbar).
            .ignoresSafeArea(.keyboard)
    }

    private var recorderTransition: PresentationLinkTransition {
        .workoutRecorder(
            dragDriver: recorderDragDriver,
            onTrayTeardownRequested: {
                // A released drag is minimizing the recorder (already slid off screen):
                // the tray sheet has to be gone before the recorder is dismissed, or
                // UIKit would forward the dismissal to it.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    recorderIsSettled = false
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
                }
            }
        )
    }

    private func showWorkoutRecorder() {
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

// MARK: - Supporting Views

/// The tab bar's accessory: the running workout's pill, or Start Workout. A view of its own so
/// that it alone observes the recorder, not the scene body that hosts the TabView (see the
/// scene's state).
private struct StartOrCurrentWorkoutButton: View {
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    @Binding var isShowingStartWorkoutSheet: Bool
    let showWorkoutRecorder: () -> Void

    var body: some View {
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
}

/// Persisting to disk failed even after the retry: without this, the data loss would be silent —
/// the UI keeps showing the in-memory objects until the app is relaunched, and only then does the
/// user find their workout gone. A modifier of its own so that it alone observes the database, not
/// the scene body.
private struct SaveFailedAlert: ViewModifier {
    @ObservedObject var database: Database

    func body(content: Content) -> some View {
        content
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

/// Weight logged elsewhere (Health app, a smart scale) arrives when the user comes back to LOGIT.
/// The anchored query only fetches what changed, so this stays cheap on every foreground. A
/// modifier of its own so that the scene body doesn't depend on the scene phase: it used to re-run
/// on every trip to the background and back, dialogs still open included.
private struct ImportBodyWeightOnForeground: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let bodyMeasurementSyncManager: BodyMeasurementSyncManager
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, isEnabled else { return }
                Task { await bodyMeasurementSyncManager.importFromHealth() }
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
