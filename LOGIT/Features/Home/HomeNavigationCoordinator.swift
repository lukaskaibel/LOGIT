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
        case let .measurementDetail(type): return "measurementDetail\(type.rawValue)"
        case let .summaryStat(metric, window): return "summaryStat\(metric.rawValue)\(window?.rawValue ?? "")"
        case let .muscleGroupDetail(group, window): return "muscleGroupDetail\(group.rawValue)\(window.rawValue)"
        case let .template(template): return "template\(String(describing: template.id))"
        case let .workout(workout): return "workout\(String(describing: workout.id))"
        default: return String(describing: self)
        }
    }

    case exercise(Exercise),
         exerciseList,
         measurementDetail(MeasurementEntryType),
         measurements,
         muscleGroupsOverview,
         // Carries the window down from Muscle Groups, which carried it from the Summary — the whole
         // chain reports over one timeframe.
         muscleGroupDetail(MuscleGroup, TrendWindow),
         muscleTargetSplit,
         progressHighlights,
         strength,
         // The optional window pins the stat screen to a timeframe (highlight cards open the chart
         // they compare over); nil — every route from the Summary itself — inherits the screen's
         // selected window, so the detail can't report a different span from the tile that opened it.
         summaryStat(WorkoutStatMetric, TrendWindow?),
         targetPerWeek,
         weeklyGoal,
         template(Template),
         templateList,
         workoutList,
         workout(Workout)
}
