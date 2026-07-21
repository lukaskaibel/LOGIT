//
//  TemplateStandardSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 10.04.22.
//

import Foundation

public extension TemplateStandardSet {
    // MARK: Legacy-field fallbacks (see TemplateSet.hasEntry)

    internal override var legacyHasEntry: Bool {
        repetitions > 0 || weight > 0
    }
}
