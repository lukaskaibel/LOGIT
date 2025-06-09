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

    var exercise: Exercise? {
        setGroup?.exercise
    }
}
