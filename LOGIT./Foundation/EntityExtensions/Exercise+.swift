//
//  Exercise+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.21.
//

import CoreData
import Foundation

extension Exercise {

    var muscleGroup: MuscleGroup? {
        get { MuscleGroup(rawValue: muscleGroupString ?? "") }
        set { muscleGroupString = newValue?.rawValue }
    }

    var setGroups: [WorkoutSetGroup] {
        get {
            return (setGroupOrder ?? .emptyList)
                .compactMap { id in
                    (setGroups_?.allObjects as? [WorkoutSetGroup])?
                        .first { setGroup in
                            setGroup.id == id
                        }
                }
        }
    }
    
    @objc var firstLetterOfName: String {
        guard let name = name, !name.isEmpty else { return " " }
        return name.first!.lowercased()
    }

    var templateSetGroups: [TemplateSetGroup] {
        get {
            return (templateSetGroupOrder ?? .emptyList)
                .compactMap { id in
                    (templateSetGroups_?.allObjects as? [TemplateSetGroup])?
                        .first {
                            templateSetGroup in
                            templateSetGroup.id == id
                        }
                }
        }
    }

    var sets: [WorkoutSet] {
        var result = [WorkoutSet]()
        for setGroup in setGroups {
            result.append(contentsOf: setGroup.sets)
        }
        return result
    }

    static let defaultExerciseNames: [String] = [
        "Push-ups",
        "Barbell Bench Press",
        "Dumbbell Bench Press",
        "Inclined Barbell Bench Press",
        "Inclined Dumbbell Bench Press",
        "Dumbbell Fly",
        "Cable Crossovers",

        "Pull-ups",
        "Chin-ups",
        "Australian Pull-ups",
        "Lat Pull-Downs",
        "Standing Barbell Rows",
        "Standing Dumbbell, Rows",
        "Sitting Rows",

        "Squats",
        "Leg Press",
        "Walking Lunges",
        "Barbell Lunges",
        "Dumbbell Lunges",
        "Leg Extension",
        "Leg Curls",
        "Deadlift",
        "Calf Raises",

        "Handstand Push-ups",
        "Military Press",
        "Shoulder Press",
        "Upright Rows",
        "Lateral Rows",
        "Rear Delt Raise",

        "Dips",
        "Tricep Pullovers",
        "Tricep Press",
        "Close Grip Bench Press",
        "Tricep Kickbacks",
        "Straight Bar Curl",
        "Dumbbell Curl",

        "Sit-ups",
        "Crunches",
        "Bicycles",
        "Leg Raises",
        "Hanging Knee Raises",
        "Plank",
        "Side Plank",

        "Face Pulls",
    ]

}

extension Array: Identifiable where Element: Exercise {

    public var id: NSManagedObjectID {
        first?.objectID ?? NSManagedObjectID()
    }

}
