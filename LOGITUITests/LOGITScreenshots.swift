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
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Screens (ordered by screenshot filename)

    func test01Home() {
        waitForTabBar()
        tapTab(at: 0)
        waitABit()
        snapshot("01_Home")
    }

    func test02MuscleGroupBack() {
        // Muscle Group Split screen with the "Back" muscle filter selected.
        // Shows the donut chart tilted toward back volume and the weekly
        // focus list for just that muscle group - more specific and more
        // marketable than the full overview.
        waitForTabBar()
        tapTab(at: 0)
        waitABit()

        let muscleGroupsTile = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Muscle Groups", "Muskelgruppen"))
            .firstMatch
        if !muscleGroupsTile.waitForExistence(timeout: 3) || !muscleGroupsTile.isHittable {
            app.swipeUp()
            waitABit()
        }
        if muscleGroupsTile.waitForExistence(timeout: 3) {
            muscleGroupsTile.tap()
            waitABit(3)
        }

        // The muscle-group selector is a segmented/horizontal list of
        // buttons. Each muscle group is its own standalone button. "Back"
        // in English / "Rücken" in German — match both.
        let backButton = app.buttons
            .matching(NSPredicate(format: "label MATCHES[c] %@ OR label MATCHES[c] %@", "^Back$", "^Rücken$"))
            .firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            waitABit(2)
        }

        snapshot("02_MuscleGroupBack")
    }

    func test03ExerciseDetail() {
        // Search tab always exposes a reliable entry point into the
        // "Exercises" list, which in turn lets us drill into a specific
        // exercise with known seeded data (Benchpress has the richest
        // personal-best history in the fixture database).
        waitForTabBar()
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
            let firstExercise = app.scrollViews.buttons.firstMatch
            if firstExercise.waitForExistence(timeout: 3) {
                firstExercise.tap()
                waitABit(3)
            }
        }

        snapshot("03_ExerciseDetail")
    }

    func test04WorkoutDetail() {
        // A completed-workout detail screen shows real sets, reps, and
        // weights so it sells the "log every rep" value prop much better
        // than the empty workout recorder. Target Push or Pull day
        // explicitly — the new "Arm Day" fixture is reserved for the
        // dedicated superset/dropset screenshot below.
        waitForTabBar()
        tapTab(at: 1)
        waitABit()

        let firstWorkout = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Push Day", "Pull Day"))
            .firstMatch
        if firstWorkout.waitForExistence(timeout: 5) {
            firstWorkout.tap()
            waitABit(3)
        } else {
            let fallback = app.scrollViews.buttons.firstMatch
            if fallback.waitForExistence(timeout: 3) {
                fallback.tap()
                waitABit(3)
            }
        }

        snapshot("04_WorkoutDetail")
    }

    func test05WorkoutRecorder() {
        // Fixtures seed a Push Day workout with `isCurrentWorkout = true`
        // AND the `-UITEST_SHOW_RECORDER` launch arg instructs LOGITApp to
        // auto-present the full-screen recorder cover shortly after launch.
        // This is more reliable than trying to tap the tabViewBottomAccessory
        // pill which swallows synthetic taps on iOS 26.
        app.terminate()
        app.launchArguments += ["-UITEST_SHOW_RECORDER", "1"]
        app.launch()

        let benchpressCell = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Benchpress"))
            .firstMatch
        _ = benchpressCell.waitForExistence(timeout: 10)
        waitABit(2)

        snapshot("05_WorkoutRecorder")
    }

    // TEMP: capture the keyboard accessory toolbar via a REAL tap on a numeric
    // set field. A real tap (unlike programmatic @FocusState focus) is what
    // attaches the `.toolbar(.keyboard)` accessory, so this is the only way to
    // screenshot the toolbar non-interactively.
    func test99KeyboardToolbar() {
        app.terminate()
        app.launchArguments += ["-UITEST_SHOW_RECORDER", "1", "-UITEST_MINIMAL", "1"]
        app.launch()

        let benchpressCell = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Benchpress"))
            .firstMatch
        _ = benchpressCell.waitForExistence(timeout: 10)
        waitABit(2)

        let h = app.frame.height
        var didTap = false
        for field in app.textFields.allElementsBoundByIndex where field.isHittable {
            let midY = field.frame.midY
            if midY > h * 0.18, midY < h * 0.6 {
                field.tap()
                didTap = true
                break
            }
        }
        if !didTap {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        }
        waitABit(2)

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "keyboard_toolbar_real"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test06SuperDropSet() {
        // Navigate to the seeded "Arm Day" workout which contains a super
        // set (Biceps Curls ↔ Triceps Extensions) immediately followed by
        // a drop set (Lateral Raises). Both visually distinct pieces of
        // the set-group cell layout land in the same frame.
        waitForTabBar()
        tapTab(at: 1)
        waitABit()

        let armDay = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Arm Day"))
            .firstMatch
        if armDay.waitForExistence(timeout: 5) {
            armDay.tap()
            waitABit(3)
        }

        // Scroll the detail screen so both set groups are visible — super
        // set is on top (short), drop set right below (taller). A small
        // swipe usually lands the frame in a good spot.
        app.swipeUp(velocity: .slow)
        waitABit(2)

        snapshot("06_SuperDropSet")
    }

    func test07LiveActivity() {
        // Replaces the Live Activity capture. Launches the app with a
        // launch-arg that swaps the root view for a Lock Screen-style
        // mockup showing both the auto rest timer and current-set cards
        // side by side (well, stacked).
        app.terminate()
        app.launchArguments += ["-UITEST_LIVE_ACTIVITY_SHOWCASE", "1"]
        app.launch()

        // The mockup is a static view; give it a moment to fade in.
        waitABit(3)

        snapshot("07_LiveActivity")
    }

    func test08BodyFat() {
        // Body Fat trend screen: line chart with selectable data points
        // showing a gentle downward slope over three months. Sells Pro
        // "Measurements" feature and lands at the end of the deck so the
        // earlier screens carry the punch.
        waitForTabBar()
        tapTab(at: 3) // Search tab - exposes "Measurements" destination.
        waitABit()

        let measurementsButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Measurements", "Messungen"))
            .firstMatch
        if measurementsButton.waitForExistence(timeout: 5) {
            measurementsButton.tap()
            waitABit(2)
        }

        let bodyFatCell = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Body Fat", "Körperfett"))
            .firstMatch
        if bodyFatCell.waitForExistence(timeout: 5) {
            bodyFatCell.tap()
            waitABit(3)
        }

        snapshot("08_BodyFat")
    }

    // MARK: - Helpers

    private func waitForTabBar() {
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 20)
    }

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
