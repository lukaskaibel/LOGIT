//
//  Database+EntityFetch.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.11.22.
//

import Foundation

extension Database {
    // MARK: - Exercise Fetch

    func getExercises(
        withNameIncluding filterText: String = "",
        for muscleGroup: MuscleGroup? = nil
    ) -> [Exercise] {
        (fetch(
            Exercise.self,
            sortingKey: "name_",
            ascending: true,
            predicate: filterText.isEmpty
                ? nil
                : NSPredicate(
                    format: "name CONTAINS[c] %@",
                    filterText
                )
        ) as! [Exercise])
            .filter { muscleGroup == nil || $0.muscleGroup == muscleGroup }
    }
    
    func getExercise(byID id: UUID) -> Exercise? {
        let exercises = fetch(
            Exercise.self,
            predicate: NSPredicate(format: "id == %@", id as CVarArg)
        ) as! [Exercise]
        return exercises.first
    }
}
