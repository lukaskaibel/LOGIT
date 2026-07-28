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
        case let .summaryStat(metric, period): return "summaryStat\(metric.rawValue)\(period?.rawValue ?? "")"
        case let .muscleGroupDetail(group, period): return "muscleGroupDetail\(group.rawValue)\(period.rawValue)"
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
         muscleGroupDetail(MuscleGroup, StatPeriod),
         muscleTargetSplit,
         progressHighlights,
         strength,
         // The optional period pins the stat screen to a window (highlight cards open the chart
         // they compare over); nil keeps the Summary's currently selected period.
         summaryStat(WorkoutStatMetric, StatPeriod?),
         targetPerWeek,
         weeklyGoal,
         template(Template),
         templateList,
         workoutList,
         workout(Workout)
}
