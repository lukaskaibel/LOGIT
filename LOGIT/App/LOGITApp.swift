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

    @State private var selectedTab: TabType = .home
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingWorkoutRecorder = false

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
                HomeScreen()
                    .zIndex(0)
                    .overlay {
                        startAndCurrentWorkoutButton
                    }
                    .fullScreenDraggableCover(isPresented: $isShowingWorkoutRecorder) {
                        WorkoutRecorderScreen()
                            .presentationBackground(.clear)
                    }
                    .sheet(isPresented: $isShowingPrivacyPolicy) {
                        NavigationStack {
                            PrivacyPolicyScreen(needsAcceptance: true)
                        }
                        .interactiveDismissDisabled()
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
                    .environment(\.goHome) { selectedTab = .home }
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
                    .onChange(of: workoutRecorder.workout) { newValue in
                        isShowingWorkoutRecorder = newValue != nil
                    }
//                #if targetEnvironment(simulator)
//                    .statusBarHidden(true)
//                #endif
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
                    isShowingWorkoutRecorder = true
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
                                isShowingWorkoutRecorder = true
                            }
                        }
                )
                .transition(.move(edge: .bottom))
            } else {
                StartWorkoutView()
                    .shadow(radius: 10)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 5)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .edgesIgnoringSafeArea(.bottom)
    }
}

// MARK: - EnvironmentValues/Keys

struct GoHomeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var goHome: () -> Void {
        get { self[GoHomeKey.self] }
        set { self[GoHomeKey.self] = newValue }
    }
}
