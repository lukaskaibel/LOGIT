//
//  TemplateSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 21.05.22.
//

import Foundation

public extension TemplateSet {
    @objc var hasEntry: Bool {
        fatalError("TemplateSet+: hasEntry must be implemented in subclass of TemplateSet")
    }

    /// Rest duration in seconds after completing this set. 0 means no rest defined.
    var restDurationSeconds: Int {
        get { Int(restDuration) }
        set { restDuration = Int64(newValue) }
    }

    var exercise: Exercise? {
        setGroup?.exercise
    }
}
