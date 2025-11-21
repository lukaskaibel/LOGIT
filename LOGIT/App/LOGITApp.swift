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

    @AppStorage("acceptedPrivacyPolicyVersion") var acceptedPrivacyPolicyVersion: Int?
    @AppStorage("setupDone") var setupDone: Bool = false

    // MARK: - State

    @StateObject private var database: Database
    @StateObject private var templateService: TemplateService
    @StateObject private var measurementController: MeasurementEntryController
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var workoutRecorder: WorkoutRecorder
    @StateObject private var muscleGroupService: MuscleGroupService
    @StateObject private var homeNavigationCoordinator = HomeNavigationCoordinator()
    @StateObject private var chronograph = Chronograph()

    @State private var selectedTab: TabType = .home
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingStartWorkoutSheet = false

    // MARK: - Init

    init() {
//        #if targetEnvironment(simulator)
//        let database = Database(isPreview: true)
//        #else
        let database = Database()
//        #endif

        _database = StateObject(wrappedValue: database)
        _templateService = StateObject(wrappedValue: TemplateService(database: database))
        _measurementController = StateObject(wrappedValue: MeasurementEntryController(database: database))
        _workoutRecorder = StateObject(wrappedValue: WorkoutRecorder(database: database))
        _muscleGroupService = StateObject(wrappedValue: MuscleGroupService())
        _homeNavigationCoordinator = StateObject(wrappedValue: HomeNavigationCoordinator())

        UserDefaults.standard.register(defaults: [
            "weightUnit": WeightUnit.kg.rawValue,
            "workoutPerWeekTarget": 3,
            "setupDone": false,
        ])
        // Fixes issue with wrong Accent Color in Alerts
        UIView.appearance().tintColor = UIColor(named: "AccentColor")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            if setupDone {
                TabView {
                    Tab("summary", systemImage: "house") {
                        HomeScreen()
        //                #if targetEnvironment(simulator)
        //                    .statusBarHidden(true)
        //                #endif
                    }
                    Tab(NSLocalizedString("exercises", comment: ""), systemImage: "dumbbell") {
                        NavigationStack {
                            ExerciseListScreen()
                        }
                    }
                    Tab(NSLocalizedString("templates", comment: ""), systemImage: "list.bullet.rectangle.portrait") {
                        NavigationStack {
                            TemplateListScreen()
                        }
                    }
                    Tab(NSLocalizedString("measurements", comment: ""), systemImage: "ruler") {
                        NavigationStack {
                            MeasurementsScreen()
                        }
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
                        .environment(\.managedObjectContext, database.context)
                        .environment(\.goHome) { selectedTab = .home }
                        .environment(\.dismissWorkoutRecorder) { dismissWorkoutRecorder() }
                }
//                    .presentation(transition: .slide, isPresented: $isShowingWorkoutRecorder) {
//                        TransitionReader { _ in
//                        }
//                    }
                .sheet(isPresented: $isShowingPrivacyPolicy) {
                    NavigationStack {
                        PrivacyPolicyScreen(needsAcceptance: true)
                    }
                    .interactiveDismissDisabled()
                }
                .task {
                    if acceptedPrivacyPolicyVersion != privacyPolicyVersion {
                        isShowingPrivacyPolicy = true
                    }
                    Task {
                        do {
                            try await purchaseManager.loadProducts()
                        } catch {
                            print(error)
                        }
                    }
                }
                .preferredColorScheme(.dark)
                .onAppear {
                    // Fixes issue with Alerts and Confirmation Dialogs not in dark mode
                    let scenes = UIApplication.shared.connectedScenes
                    guard let scene = scenes.first as? UIWindowScene else { return }
                    scene.keyWindow?.overrideUserInterfaceStyle = .dark
                }
            } else {
                FirstStartScreen()
                    .environmentObject(database)
                    .preferredColorScheme(.dark)
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
                    StartWorkoutView()
                        .frame(maxWidth: .infinity)
                )
//                    .shadow(radius: 10)
//                    .padding(.horizontal, 12)
//                    .padding(.bottom, 5)
//                    .environment(\.presentWorkoutRecorder) { showWorkoutRecorder() }
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
                        StartWorkoutView()
                            .shadow(radius: 10)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 5)
                            .environment(\.presentWorkoutRecorder) { showWorkoutRecorder() }
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
