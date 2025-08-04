//
//  HomeNavigationCoordinator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.12.24.
//

import SwiftUI

class HomeNavigationCoordinator: ObservableObject {
    @Published var path: [HomeNavigationDestinationType] = []
    @Published var isPresentingWorkoutRecorder = false
}

enum HomeNavigationDestinationType: Hashable, Identifiable, Equatable {
    var id: String {
        switch self {
        case let .exercise(exercise): return "exercise\(String(describing: exercise.id))"
        case let .template(template): return "template\(String(describing: template.id))"
        case let .workout(workout): return "workout\(String(describing: workout.id))"
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
