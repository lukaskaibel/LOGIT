//
//  DropSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 13.05.22.
//

import Foundation

public extension DropSet {
    var numberOfDrops: Int {
        repetitions?.count ?? 0
    }

    func addDrop() {
        repetitions?.append(0)
        weights?.append(0)
    }

    func removeLastDrop() {
        if repetitions?.count ?? 0 > 1, weights?.count ?? 0 > 1 {
            repetitions?.removeLast()
            weights?.removeLast()
        }
    }

    // MARK: Overrides from WorkoutSet

    override var hasEntry: Bool {
        (repetitions?.reduce(0, +) ?? 0) > 0 || (weights?.reduce(0, +) ?? 0) > 0
    }

    override func clearEntries() {
        repetitions = Array(repeating: 0, count: repetitions?.count ?? 0)
        weights = Array(repeating: 0, count: weights?.count ?? 0)
    }
}
