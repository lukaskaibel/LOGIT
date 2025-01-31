//
//  TemplatePredicateFactory.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import Foundation

struct TemplatePredicateFactory {
    
    static func getTemplates(
        nameIncluding nameSubstring: String = "",
        withMuscleGroup muscleGroup: MuscleGroup? = nil
    ) -> NSPredicate? {
        var subpredicates = [NSPredicate]()

        if !nameSubstring.isEmpty {
            let namePredicate = NSPredicate(format: "name CONTAINS[c] %@", nameSubstring)
            subpredicates.append(namePredicate)
        }

        if let muscleGroup = muscleGroup {
            let muscleGroupPredicate = NSPredicate(
                format: """
                SUBQUERY(
                   setGroups_, $sg,
                   SUBQUERY($sg.exercises_, $ex, $ex.muscleGroupString == %@).@count > 0
                ).@count > 0
                """,
                muscleGroup.rawValue
            )
            subpredicates.append(muscleGroupPredicate)
        }
        
        if subpredicates.isEmpty {
            return nil
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
    }

    
}
