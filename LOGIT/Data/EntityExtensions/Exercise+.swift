//
//  Exercise+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.21.
//

import CoreData
import Foundation
import Ifrit

// MARK: - Searchable Conformance

extension Exercise: Searchable {
    public var properties: [FuseProp] {
        [FuseProp(displayName, weight: 1.0)]
    }
}

// MARK: - Exercise Extension

extension Exercise {
    var displayName: String {
        guard let name = name, !name.isEmpty else { 
            return NSLocalizedString("noName", comment: "")
        }
        if name.hasPrefix("_default.") {
            return NSLocalizedString(name, comment: "")
        }
        return name
    }
    
    var displayNameFirstLetter: String {
        let display = displayName
        return display.isEmpty ? " " : String(display.prefix(1).uppercased())
    }
    
    var muscleGroup: MuscleGroup? {
        get { MuscleGroup(rawValue: muscleGroupString ?? "") }
        set { muscleGroupString = newValue?.rawValue }
    }

    var setGroups: [WorkoutSetGroup] {
        return (setGroupOrder ?? .emptyList)
            .compactMap { id in
                (setGroups_?.allObjects as? [WorkoutSetGroup])?
                    .first { setGroup in
                        setGroup.id == id
                    }
            }
    }

    @objc var firstLetterOfName: String {
        return displayNameFirstLetter
    }

    var templateSetGroups: [TemplateSetGroup] {
        return (templateSetGroupOrder ?? .emptyList)
            .compactMap { id in
                (templateSetGroups_?.allObjects as? [TemplateSetGroup])?
                    .first {
                        templateSetGroup in
                        templateSetGroup.id == id
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
