//
//  LOGITScreenshots.swift
//  LOGITUITests
//
//  Captures marketing screenshots for the App Store via fastlane snapshot.
//  Each test launches the app straight to one screen and calls `snapshot(name)`
//  so the captured PNGs share a filename convention with the entries in
//  `fastlane/screenshots/<locale>/title.strings` (so frameit can overlay the
//  right headline on each frame).
//
//  Run via fastlane:
//      bundle exec fastlane screenshots
//
//  Navigation is driven entirely by launch arguments — `-UITEST_FIXTURES 1`
//  swaps in the seeded in-memory preview store, and `-UITEST_DEEPLINK <target>`
//  (or `-UITEST_SHOW_RECORDER` / `-UITEST_LIVE_ACTIVITY_SHOWCASE`) opens a
//  specific screen. The previous suite tapped cells by their English label,
//  which silently landed on the wrong screen in every non-English locale;
//  deep-linking keeps all nine locales correct with no fragile taps.
//

import XCTest

@MainActor
final class LOGITScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Launch

    /// Fresh app on the seeded fixtures, plus any extra launch arguments. The
    /// UI test target is a standalone bundle (no "Target Application" wiring),
    /// hence the explicit bundle identifier.
    private func launch(_ extraArguments: [String] = []) {
        app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        setupSnapshot(app)
        app.launchArguments += ["-UITEST_FIXTURES", "1"] + extraArguments
        app.launch()
    }

    // MARK: - Screens (ordered by screenshot filename)

    /// The Summary hero: weekly-goal strip, effort tiles and the muscle-balance
    /// tile — the redesigned home for 5.0.
    func test01Summary() {
        launch()
        waitForTabBar()
        waitABit(2)
        snapshot("01_Summary")
    }

    /// The new Progress tab: the overall strength trend plus the pinned exercise
    /// tiles. The app itself scrolls to a fixed anchor in this mode (HomeScreen's
    /// screenshot `.task`), so the pinned tiles clear the Start Workout bar with
    /// the Highlights still in view — deterministically, without a flaky gesture.
    func test02Progress() {
        launch(["-UITEST_DEEPLINK", "progress"])
        waitForTabBar()
        waitABit(3)
        snapshot("02_Progress")
    }

    /// The Workout Goal screen led by the weekly-streak scoreboard.
    func test03Streak() {
        launch(["-UITEST_DEEPLINK", "goal"])
        waitForPushedScreen()
        snapshot("03_Streak")
    }

    /// The Muscle Groups overview: occurrence donut + diverging balance bars.
    func test04MuscleBalance() {
        launch(["-UITEST_DEEPLINK", "muscleOverview"])
        waitForPushedScreen()
        snapshot("04_MuscleBalance")
    }

    /// A single exercise's progress: metric tiles, chart and personal records.
    func test05ExerciseDetail() {
        launch(["-UITEST_DEEPLINK", "exerciseDetail"])
        waitForPushedScreen()
        snapshot("05_ExerciseDetail")
    }

    /// The full-screen workout recorder mid-session (auto-presented at launch).
    func test06Recorder() {
        launch(["-UITEST_SHOW_RECORDER", "1"])
        // The recorder cover auto-presents ~0.6s after the tab view appears.
        waitABit(5)
        snapshot("06_Recorder")
    }

    /// A completed workout showing a superset and a drop set back to back.
    func test07SuperDropSet() {
        launch(["-UITEST_DEEPLINK", "workoutDetail"])
        waitForPushedScreen()
        // Scroll past the stat tiles so both set groups — the superset and the
        // drop set right below it — land in frame together.
        app.swipeUp(velocity: .slow)
        waitABit(2)
        snapshot("07_SuperDropSet")
    }

    /// Lock Screen-style composition of the Live Activity cards.
    func test08LiveActivity() {
        launch(["-UITEST_LIVE_ACTIVITY_SHOWCASE", "1"])
        waitABit(3)
        snapshot("08_LiveActivity")
    }

    /// The Pro Measurements body-fat trend chart.
    func test09BodyMeasurements() {
        launch(["-UITEST_DEEPLINK", "measurement"])
        waitForPushedScreen()
        snapshot("09_BodyMeasurements")
    }

    // MARK: - Helpers

    private func waitForTabBar() {
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
    }

    /// Waits for a launch deep link to push its detail screen (a navigation bar
    /// back button appears), then lets it settle. Language-independent.
    private func waitForPushedScreen() {
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
        _ = app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10)
        waitABit(2)
    }

    private func waitABit(_ seconds: UInt32 = 1) {
        sleep(seconds)
    }
}
