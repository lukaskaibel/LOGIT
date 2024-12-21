//
//  EnvironmentValues+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 29.07.23.
//

import SwiftUI

public var privacyPolicyVersion = 2

private struct CanEditKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var canEdit: Bool {
        get { self[CanEditKey.self] }
        set { self[CanEditKey.self] = newValue }
    }
}
