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

    #if targetEnvironment(simulator)
        @StateObject private var database = Database.preview
        @StateObject private var templateService = TemplateService(database: Database.preview)
        @StateObject private var measurementController = MeasurementEntryController.preview
    #else
        @StateObject private var database = Database.shared
        @StateObject private var templateService = TemplateService(database: Database.shared)
        @StateObject private var measurementController = MeasurementEntryController.shared
    #endif
    @State private var selectedTab: TabType = .home

    // MARK: - Init

    init() {
        UserDefaults.standard.register(defaults: [
            "weightUnit": WeightUnit.kg.rawValue,
            "workoutPerWeekTarget": 3,
            "setupDone": false,
        ])
        //Fixes issue with wrong Accent Color in Alerts
        UIView.appearance().tintColor = UIColor(named: "AccentColor")

        // MARK: - Test Methods
        //testLanguage()
        // testFirstStart()
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            if setupDone {
                TabView(selection: $selectedTab) {
                    HomeScreen()
                        .tabItem {
                            Label(
                                NSLocalizedString("home", comment: ""),
                                systemImage: "house.fill"
                            )
                        }
                        .tag(TabType.home)
                    NavigationStack {
                        WorkoutListScreen()
                    }
                    .tabItem {
                        Label(
                            NSLocalizedString("workoutHistory", comment: ""),
                            systemImage: "clock"
                        )
                    }
                    .tag(TabType.templates)
                    NavigationStack {
                        StartWorkoutScreen()
                    }
                    .tabItem {
                        Label(
                            NSLocalizedString("startWorkout", comment: ""),
                            systemImage: "plus"
                        )
                    }
                    .tag(TabType.startWorkout)
                    NavigationStack {
                        MeasurementsScreen()
                    }
                    .tabItem {
                        Label(
                            NSLocalizedString("measurements", comment: ""),
                            systemImage: "ruler"
                        )
                    }
                    .tag(TabType.exercises)
                    NavigationStack {
                        SettingsScreen()
                    }
                    .tabItem {
                        Label(
                            NSLocalizedString("settings", comment: ""),
                            systemImage: "gear"
                        )
                    }
                    .tag(TabType.settings)
                }
                .environmentObject(database)
                .environmentObject(measurementController)
                .environmentObject(templateService)
                .environment(\.goHome, { selectedTab = .home })
                .preferredColorScheme(.dark)
                #if targetEnvironment(simulator)
                    .statusBarHidden(true)
                #endif
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
