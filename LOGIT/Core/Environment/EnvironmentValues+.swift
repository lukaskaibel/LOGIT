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

private struct SuppressIntegerFieldFocusKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var canEdit: Bool {
        get { self[CanEditKey.self] }
        set { self[CanEditKey.self] = newValue }
    }

    var isIntegerFieldFocusSuppressed: Bool {
        get { self[SuppressIntegerFieldFocusKey.self] }
        set { self[SuppressIntegerFieldFocusKey.self] = newValue }
    }
}

extension View {
    func suppressIntegerFieldFocus(_ suppressed: Bool) -> some View {
        environment(\.isIntegerFieldFocusSuppressed, suppressed)
    }
}
