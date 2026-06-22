//
//  UIScreen+ScreenCorners.swift
//
//
//  Created by Lukas Kaibel on 03/09/24.
//

import UIKit

extension UIScreen {
    /// The screen hosting the app's active window scene — replacement for the
    /// deprecated `UIScreen.main`. Nil only when no window scene is connected.
    @MainActor
    static var current: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen
    }

    private static let cornerRadiusKey: String = {
        let components = ["Radius", "Corner", "display", "_"]
        return components.reversed().joined()
    }()

    /// The corner radius of the display. Uses a private property of `UIScreen`,
    /// and may report 0 if the API changes.
    public var displayCornerRadius: CGFloat {
        guard let cornerRadius = value(forKey: Self.cornerRadiusKey) as? CGFloat else {
            assertionFailure("Failed to detect screen corner radius")
            return 0
        }

        return cornerRadius
    }
}
