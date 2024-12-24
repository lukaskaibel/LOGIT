//
//  Database+EntityEdit.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 03.11.22.
//

import Foundation

extension Database {

    public func addSet(to setGroup: WorkoutSetGroup) {
        let lastSet = setGroup.sets.last
        if let _ = lastSet as? DropSet {
            newDropSet(setGroup: setGroup)
        } else if let _ = lastSet as? SuperSet {
            newSuperSet(setGroup: setGroup)
        } else {
            newStandardSet(setGroup: setGroup)
        }
    }

    public func addSet(to templateSetGroup: TemplateSetGroup) {
        let lastSet = templateSetGroup.sets.last
        if let _ = lastSet as? TemplateDropSet {
            newTemplateDropSet(templateSetGroup: templateSetGroup)
        } else if let _ = lastSet as? TemplateSuperSet {
            newTemplateSuperSet(setGroup: templateSetGroup)
        } else {
            newTemplateStandardSet(setGroup: templateSetGroup)
        }
    }

}
