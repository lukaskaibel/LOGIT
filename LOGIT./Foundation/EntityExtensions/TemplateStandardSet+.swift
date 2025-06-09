//
//  TemplateStandardSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 10.04.22.
//

import Foundation

public extension TemplateStandardSet {
    // MARK: Overrides from TemplateSet

    override var hasEntry: Bool {
        repetitions > 0 || weight > 0
    }
}
