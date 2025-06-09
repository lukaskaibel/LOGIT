//
//  Binding+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 08.02.23.
//

import SwiftUI

extension Binding where Value == String {
    func max(_ limit: Int) -> Self {
        if wrappedValue.count > limit {
            DispatchQueue.main.async {
                self.wrappedValue = String(self.wrappedValue.dropLast())
            }
        }
        return self
    }
}
