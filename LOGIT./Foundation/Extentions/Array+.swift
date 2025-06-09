//
//  Array+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 01.03.22.
//

import Foundation

extension Array {
    static var emptyList: [Element] { [Element]() }

    var second: Element? {
        value(at: 1)
    }

    func elements(for indexSet: IndexSet) -> [Element] {
        var result = [Element]()
        for i in indexSet {
            result.append(self[i])
        }
        return result
    }

    /// Index safe operation for retrieving the arrays element at a given index.
    /// - Parameter index: Index for the element that should be returned.
    /// - Returns: The value at given index if it is contained in the array. Otherwise returns nil.
    func value(at index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }

    /// Index safe operation for setting arrays value at given index. If the index is out of range the value won't be inserted.
    /// - Parameters:
    ///   - index: Index that should be replaced
    ///   - value: New value for the given index
    mutating func replaceValue(at index: Int, with value: Element) {
        guard indices.contains(index) else { return }
        self[index] = value
    }
}

extension Array where Element: Comparable {
    mutating func remove(_ element: Element) {
        self = filter { $0 != element }
    }
}
