//
//  HomeNavigation.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.12.24.
//

import SwiftUI

class HomeNavigationCoordinator: ObservableObject {
    @Published var path: [HomeNavigationDestinationType] = []
}

enum HomeNavigationDestinationType: Hashable, Identifiable {
    var id: String {
        switch self {
        case .exercise(let exercise): return "exercise\(String(describing: exercise.id))"
        case .template(let template): return "template\(String(describing: template.id))"
        case .workout(let workout): return "workout\(String(describing: workout.id))"
        default: return String(describing: self)
        }
    }
    
    case exercise(Exercise),
         exerciseList,
         measurements,
         muscleGroupsOverview,
         overallSets,
         targetPerWeek,
         template(Template),
         templateList,
         workoutList,
         workout(Workout),
         volume
}
