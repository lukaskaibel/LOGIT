//
//  LOGITScreenshots.swift
//  LOGITUITests
//
//  Captures marketing screenshots for the App Store via fastlane snapshot.
//  Each test navigates the app to a specific screen and calls `snapshot(name)`
//  so the captured PNGs share a filename convention with the entries in
//  `fastlane/screenshots/<locale>/title.strings` (so frameit can overlay the
//  right headline on each frame).
//
//  Run via fastlane:
//      bundle exec fastlane screenshots
//
//  The host app is launched with `-UITEST_FIXTURES 1`, which swaps in a seeded
//  in-memory CoreData store via `ScreenshotFixtures` + `Database(isPreview:)`.
//

import XCTest

@MainActor
final class LOGITScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Explicit bundle ID because the UI test target is added as a
        // standalone bundle (no "Target Application" wiring in the scheme),
        // so XCUIApplication() would otherwise try to launch the test bundle
        // itself.
        app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        setupSnapshot(app)
        app.launchArguments += ["-UITEST_FIXTURES", "1"]
        app.launch()

        // Tab bar is the most stable "app is ready" signal.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 20),
            "Tab bar never appeared - did the app crash on launch?"
        )
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Screens

    func test01Home() {
        tapTab(at: 0)
        waitABit()
        snapshot("01_Home")
    }

    func test02History() {
        tapTab(at: 1)
        waitABit()
        snapshot("02_History")
    }

    func test03Templates() {
        tapTab(at: 2)
        waitABit()
        snapshot("03_Templates")
    }

    func test04ExerciseDetail() {
        // Search tab always exposes a reliable entry point into the
        // "Exercises" list, which in turn lets us drill into a specific
        // exercise with known seeded data (Benchpress has the richest
        // personal-best history in the fixture database).
        tapTab(at: 3)
        waitABit()

        let exercisesButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Exercises"))
            .firstMatch
        if exercisesButton.waitForExistence(timeout: 5) {
            exercisesButton.tap()
            waitABit(2)
        }

        let benchpress = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Benchpress"))
            .firstMatch
        if benchpress.waitForExistence(timeout: 5) {
            benchpress.tap()
            waitABit(3)
        } else {
            // Fallback to whatever exercise is first so we still get a
            // useful "detail" screen even if the seeding changes.
            let firstExercise = app.scrollViews.buttons.firstMatch
            if firstExercise.waitForExistence(timeout: 3) {
                firstExercise.tap()
                waitABit(3)
            }
        }

        snapshot("04_ExerciseDetail")
    }

    func test05WorkoutDetail() {
        // A completed-workout detail screen shows real sets, reps, and
        // weights so it sells the "log every rep" value prop much better
        // than the empty workout recorder.
        tapTab(at: 1)
        waitABit()

        let firstWorkout = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Push Day", "Pull Day"))
            .firstMatch
        if firstWorkout.waitForExistence(timeout: 5) {
            firstWorkout.tap()
            waitABit(3)
        } else {
            // Fallback to whatever's on top.
            let fallback = app.scrollViews.buttons.firstMatch
            if fallback.waitForExistence(timeout: 3) {
                fallback.tap()
                waitABit(3)
            }
        }

        snapshot("05_WorkoutDetail")
    }

    // MARK: - Helpers

    private func tapTab(at index: Int) {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else { return }
        let buttons = tabBar.buttons.allElementsBoundByIndex
        guard index < buttons.count else { return }
        buttons[index].tap()
    }

    private func waitABit(_ seconds: UInt32 = 1) {
        sleep(seconds)
    }
}
