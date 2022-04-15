//
//  LOGITApp.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.21.
//

import SwiftUI

@main
struct LOGIT: App {
    
    @AppStorage("setupDone") var setupDone: Bool = false
    
    init() {
        UserDefaults.standard.register(defaults: [
            "weightUnit" : WeightUnit.kg.rawValue,
            "workoutPerWeekTarget" : 3,
            "setupDone" : false
        ])
        UserDefaults.standard.set(["de"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        //FirstStartView Test
//        UserDefaults.standard.set(false, forKey: "setupDone")
        
        //Fixes issue with wrong Accent Color in Alerts
        UIView.appearance().tintColor = UIColor(named: "AccentColor")
    }
    
    let database = Database.shared

    var body: some Scene {
        WindowGroup {
            if setupDone {
                TabView {
                    HomeView(context: database.container.viewContext)
                        .tabItem { Label("Home", systemImage: "house") }
                    NavigationView {
                        WorkoutTemplateListView()
                    }.tabItem { Label(NSLocalizedString("templates", comment: ""), systemImage: "list.bullet.rectangle.portrait") }
                    NavigationView {
                        AllExercisesView()
                    }.tabItem { Label(NSLocalizedString("exercises", comment: ""), systemImage: "stopwatch") }
                }.environment(\.managedObjectContext, database.container.viewContext)
            } else {
                FirstStartView()
            }
        }
    }
}

