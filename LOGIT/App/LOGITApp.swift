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
    @StateObject private var workoutRecorder: WorkoutRecorder
    @StateObject private var workoutLiveActivityManager: WorkoutLiveActivityManager
    @StateObject private var muscleGroupService: MuscleGroupService
    @StateObject private var homeNavigationCoordinator = HomeNavigationCoordinator()
    @StateObject private var chronograph: Chronograph
    @StateObject private var defaultExerciseService: DefaultExerciseService
    @StateObject private var exerciseSuggestionService: ExerciseSuggestionService

    @State private var selectedTab: TabType = .home
    @State private var isShowingWelcome = false
    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingStartWorkoutSheet = false
    @State private var isShowingLiveActivityShowcase = false
    #if DEBUG
    @State private var isShowingKbdTest = false
    @State private var uiTestMetricExercise: Exercise?
    #endif

    // Import handling state
    @State private var importedWorkout: Workout?
    @State private var importedTemplate: Template?
    @State private var showingImportError = false
    @State private var importErrorMessage = ""

    // MARK: - Init

    init() {
        ScreenshotFixtures.prepareUserDefaultsIfNeeded()

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
                    Tab("summary", systemImage: "house") {
                        HomeScreen()
        //                #if targetEnvironment(simulator)
        //                    .statusBarHidden(true)
        //                #endif
                    }
                    Tab(NSLocalizedString("history", comment: ""), systemImage: "clock.arrow.circlepath") {
                        NavigationStack {
                            WorkoutListScreen()
                        }
                    }
                    Tab(NSLocalizedString("templates", comment: ""), systemImage: "list.bullet.rectangle.portrait") {
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
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-UITEST_KBD_TEST") {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        isShowingKbdTest = true
                    }
                    if ProcessInfo.processInfo.arguments.contains("-UITEST_METRIC_DETAIL") {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        uiTestMetricExercise = database.getExercises().first(where: { $0.displayName.contains("Bench") })
                            ?? database.getExercises().max(by: { $0.sets.count < $1.sets.count })
                    }
                    #endif
                }
                .fullScreenCover(isPresented: $isShowingLiveActivityShowcase) {
                    LiveActivityShowcaseView()
                }
                #if DEBUG
                .fullScreenDraggableCover(isPresented: $isShowingKbdTest) {
                    KbdToolbarReferenceView()
                        .environmentObject(database)
                        .environmentObject(workoutRecorder)
                        .environmentObject(muscleGroupService)
                        .environmentObject(chronograph)
                }
                .fullScreenCover(item: $uiTestMetricExercise) { exercise in
                    NavigationStack {
                        ExerciseWeightScreen(exercise: exercise, workoutSets: exercise.sets)
                    }
                    .environmentObject(database)
                    .environmentObject(purchaseManager)
                    .environmentObject(muscleGroupService)
                    .environment(\.managedObjectContext, database.context)
                    .preferredColorScheme(.dark)
                }
                #endif
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

#if DEBUG
// TEMP: reference screen to compare the keyboard accessory toolbar gap in a
// plain context (no draggable cover, no sheet). Presented via -UITEST_KBD_TEST.
struct KbdToolbarReferenceView: View {
    // Observe the same heavy objects the recorder does (chronograph publishes
    // on a timer) to see if continuous re-render collapses the toolbar gap.
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder
    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var chronograph: Chronograph

    @State private var texts: [String] = Array(repeating: "0", count: 12)
    @State private var showFullToolbar = false
    @FocusState private var focusedField: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollViewReader { _ in
                    ScrollView {
                        VStack(spacing: 24) {
                            Color.clear.frame(height: 320)
                            ForEach(0..<12, id: \.self) { i in
                                TextField("0", text: $texts[i])
                                    .focused($focusedField, equals: i)
                                    .keyboardType(.numberPad)
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .fixedSize()
                                    .foregroundStyle(focusedField == i ? Color.black : Color.white)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .background(focusedField == i ? Color.white : Color.black.opacity(0.000001))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .scaleEffect(focusedField == i ? 1.05 : 1.0)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.6, blendDuration: 0), value: focusedField)
                                    .frame(minWidth: 100, alignment: .trailing)
                                    .onTapGesture { focusedField = i }
                            }
                            .onChange(of: focusedField) { _, newValue in
                                showFullToolbar = newValue != nil
                            }
                            Color.clear.frame(height: 320)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 100)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    HStack {
                        Spacer()
                        if showFullToolbar {
                            Button {} label: {
                                Image(systemName: "chevron.up").keyboardToolbarButtonStyle()
                            }
                            Button {} label: {
                                Image(systemName: "chevron.down").keyboardToolbarButtonStyle()
                            }
                        }
                        Button {} label: {
                            Image(systemName: "keyboard.chevron.compact.down").keyboardToolbarButtonStyle()
                        }
                        if showFullToolbar {
                            Spacer()
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .statusBarHidden(true)
    }
}
#endif
