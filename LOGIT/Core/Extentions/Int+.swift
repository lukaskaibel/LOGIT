//
//  Int+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 23.03.22.
//

import SwiftUI

extension Int {
    var cgFloat: CGFloat {
        CGFloat(self)
    }

    /// Formats the integer (seconds) as a compact rest time string, e.g. "1:30", "0:30", "3:00".
    var restTimeString: String {
        let m = self / 60
        let s = self % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
