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

    /// The top of the merged Summary: the title row's weekly-goal arc, the
    /// timeframe picker, then the Strength and Balance pair over the 2×2 core
    /// stat tiles — one screen since This Week and Progress merged in #113.
    func test01Summary() {
        launch()
        waitForTabBar()
        waitABit(2)
        snapshot("01_Summary")
    }

    /// The lower half of the merged Summary: the core stat grid, muscle balance and
    /// the pinned exercise tiles. The app itself scrolls to a fixed anchor in this
    /// mode (HomeScreen's screenshot `.task`), so the pinned tiles clear the Start
    /// Workout bar — deterministically, without a flaky gesture. (The `progress`
    /// target name predates the tab merge; the fastlane title strings key off the
    /// `02_Progress` file name, so both stay put.)
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

    /// The Muscle Groups overview: the "groups at target" hero over the
    /// `MuscleBalanceTrackChart`, then the eight groups as a two-column grid
    /// split by verdict (below target first, then at target, then overshoot),
    /// each section under a circled chevron/check header. (The donut and the
    /// diverging balance bars this comment used to describe were both removed
    /// in #124.)
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

    /// The Strength detail screen — 5.1's headline addition: the strength trend
    /// over the selected window, the About section and the strongest-lifts list.
    func test10Strength() {
        launch(["-UITEST_DEEPLINK", "strength"])
        waitForPushedScreen()
        snapshot("10_Strength")
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
