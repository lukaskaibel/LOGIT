//
//  StandardSet+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.06.21.
//

import Foundation

public extension StandardSet {
    // MARK: Legacy-field fallbacks (see WorkoutSet.hasEntry & friends)

    internal override var legacyHasEntry: Bool {
        repetitions > 0 || weight > 0
    }

    internal override var legacyHasRepetitionEntry: Bool {
        repetitions > 0
    }

    internal override func legacyClearEntries() {
        repetitions = 0
        weight = 0
    }
}
