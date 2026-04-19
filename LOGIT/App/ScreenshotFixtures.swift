//
//  ScreenshotFixtures.swift
//  LOGIT
//
//  Support for the fastlane screenshot pipeline. When the app is launched with
//  `-UITEST_FIXTURES 1` the UI test host bypasses the regular CloudKit-backed
//  CoreData store and instead boots the curated in-memory preview database so
//  every screenshot shows the same, polished dataset regardless of what lives
//  in the simulator.
//

import Foundation

enum ScreenshotFixtures {
    /// Returns `true` when the app was launched by fastlane snapshot with the
    /// fixture flag. Checking the arguments once at process start keeps the
    /// hot path out of normal user sessions.
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITEST_FIXTURES") || args.contains("UITEST_FIXTURES")
    }

    /// Returns `true` when the UI test wants the workout recorder cover
    /// auto-presented at launch. We need this because the iOS 26
    /// `tabViewBottomAccessory` pill isn't reliably tappable via XCUITest's
    /// synthetic events, so the test sets this flag instead of trying to
    /// tap the pill after the app has launched.
    static var shouldAutoPresentRecorder: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITEST_SHOW_RECORDER") || args.contains("UITEST_SHOW_RECORDER")
    }

    /// When set, LOGITApp swaps its entire root view for the
    /// `LiveActivityShowcaseView` marketing mockup. The real app never needs
    /// this; it exists purely so fastlane can capture a Lock Screen-style
    /// composition of the Live Activity widgets (auto rest timer + current
    /// set) in one shot, without staging two simulators and merging PNGs.
    static var shouldShowLiveActivityShowcase: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITEST_LIVE_ACTIVITY_SHOWCASE")
            || args.contains("UITEST_LIVE_ACTIVITY_SHOWCASE")
    }

    /// Called very early in `LOGITApp.init` so defaults are in place before
    /// any `@AppStorage` reads happen.
    static func prepareUserDefaultsIfNeeded() {
        guard isEnabled else { return }

        let defaults = UserDefaults.standard
        // Skip the onboarding / first start screen.
        defaults.set(true, forKey: "setupDone")
        // Deterministic unit so screenshots are identical across locales.
        defaults.set(WeightUnit.kg.rawValue, forKey: "weightUnit")
        // A visible weekly goal makes the home ring look populated.
        defaults.set(4, forKey: "workoutPerWeekTarget")
    }
}
