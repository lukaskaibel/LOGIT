//
//  StandardSet+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.06.21.
//

import Foundation

public extension StandardSet {
    // MARK: Overrides from WorkoutSet

    override var hasEntry: Bool {
        repetitions > 0 || weight > 0
    }

    override func clearEntries() {
        repetitions = 0
        weight = 0
    }
}
