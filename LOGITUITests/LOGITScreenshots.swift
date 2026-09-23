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
    //
    // The store shows the first three in search results, so they carry the core loop: the overview,
    // logging a workout, and what the workout achieved. Progress detail follows, then the rest.

    /// The top of the merged Summary: the title row's weekly-goal arc, the timeframe picker, then the
    /// Strength and Balance pair over the 2×2 core stat tiles.
    func test01Summary() {
        launch()
        waitForTabBar()
        // The fixtures load after the tab bar appears; captured too early this was the empty state
        // ("Log your first workout"), and that image reached App Store Connect for 5.2. The Balance
        // tile only exists once there is data, so wait for it and fail rather than capture without.
        XCTAssertTrue(
            app.descendants(matching: .any)["balanceTile"].firstMatch.waitForExistence(timeout: 20),
            "Summary never showed its data — refusing to capture the empty state"
        )
        waitABit(2)
        snapshot("01_Summary")
    }

    /// The workout recorder mid-session, opened at the top of the list: the top sheet on its actions
    /// stop (Minimize, Finish) over whole exercise cards. Scrolled to its end, as the recorder opens
    /// for real, the first visible card's header sat under the sheet since #209.
    func test02Recorder() {
        launch(["-UITEST_SHOW_RECORDER", "1", "-UITEST_NO_SCROLLTO"])
        XCTAssertTrue(recorderFinishButton.waitForExistence(timeout: 20), "Recorder never presented")
        waitABit(3)
        snapshot("02_Recorder")
    }

    /// The finish panel, 5.2's end of a workout: the week's goal, the session's records and
    /// improvements, then its effort and note.
    func test03Finish() {
        launch(["-UITEST_SHOW_RECORDER", "1", "-UITEST_NO_SCROLLTO"])
        XCTAssertTrue(recorderFinishButton.waitForExistence(timeout: 20), "Recorder never presented")
        waitABit(2)
        recorderFinishButton.tap()
        XCTAssertTrue(
            app.otherElements["finishGoalHero"].firstMatch.waitForExistence(timeout: 10),
            "The finish panel never showed its weekly goal"
        )
        // The panel reveals itself in beats (the week, then the records, then the rest).
        waitABit(5)
        snapshot("03_Finish")
    }

    /// The Strength detail screen: the strength trend over the selected window, the per-muscle
    /// breakdown and the strongest lifts.
    func test04Strength() {
        launch(["-UITEST_DEEPLINK", "strength"])
        waitForPushedScreen()
        snapshot("04_Strength")
    }

    /// Muscle Groups: "Behind on" over the lettered weekly-set chart, then every group under
    /// Below / At / Above target.
    func test05MuscleBalance() {
        launch(["-UITEST_DEEPLINK", "muscleOverview"])
        waitForPushedScreen()
        snapshot("05_MuscleBalance")
    }

    /// The Workout Goal screen: this week's arc, the week strip and the streak's milestone chain.
    func test06Streak() {
        launch(["-UITEST_DEEPLINK", "goal"])
        waitForPushedScreen()
        snapshot("06_Streak")
    }

    /// A single exercise's progress: metric tiles, chart and personal records.
    func test07ExerciseDetail() {
        launch(["-UITEST_DEEPLINK", "exerciseDetail"])
        waitForPushedScreen()
        snapshot("07_ExerciseDetail")
    }

    /// Lock Screen composition of the real Live Activity: the rest timer and a set being logged.
    func test08LiveActivity() {
        launch(["-UITEST_LIVE_ACTIVITY_SHOWCASE", "1"])
        waitABit(3)
        snapshot("08_LiveActivity")
    }

    /// A completed workout showing its effort, a superset and a drop set back to back.
    func test09SuperDropSet() {
        launch(["-UITEST_DEEPLINK", "workoutDetail"])
        waitForPushedScreen()
        // Scroll past the stat tiles so both set groups — the superset and the
        // drop set right below it — land in frame together.
        app.swipeUp(velocity: .slow)
        waitABit(2)
        snapshot("09_SuperDropSet")
    }

    /// The Pro Measurements body-fat trend chart.
    func test10BodyMeasurements() {
        launch(["-UITEST_DEEPLINK", "measurement"])
        waitForPushedScreen()
        snapshot("10_BodyMeasurements")
    }

    // MARK: - Helpers

    /// The recorder's Finish button, by identifier: its label is localized.
    private var recorderFinishButton: XCUIElement {
        app.buttons["recorderFinishButton"].firstMatch
    }

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
