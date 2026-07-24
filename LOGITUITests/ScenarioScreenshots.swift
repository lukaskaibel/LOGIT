//
//  ScenarioScreenshots.swift
//  LOGITUITests
//
//  Standing verification suite: captures the app's main screens in each launch
//  scenario (see LOGIT/App/TestScenarios.swift) so UI changes can be checked
//  against the critical data states — brand-new user (empty), single workout
//  (one), long-time user (many), and the free tier (many + -UITEST_FORCE_FREE).
//
//  Run on the iOS 26.4 simulator (the 26.0 test runner dies nondeterministically):
//      xcodebuild test -workspace LOGIT.xcworkspace -scheme LOGITScreenshots \
//        -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
//        -only-testing:LOGITUITests/ScenarioScreenshots \
//        -resultBundlePath scenarios.xcresult
//      xcrun xcresulttool export attachments --path scenarios.xcresult --output-path <dir>
//
//  Screenshots land as attachments named <scenario>_<NN>_<screen>. For screens
//  the tab-root walkthrough doesn't reach, temporarily add a test method here
//  that launches via launchApp(scenario:) and navigates there (one launch per
//  test method — relaunching within a method kills the iOS 26 test runner).
//

import XCTest

@MainActor
final class ScenarioScreenshots: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Keep capturing later screens even if one navigation step fails.
        continueAfterFailure = true
    }

    // MARK: - Scenarios

    func testEmptyScenario() {
        captureMainScreens(scenario: "empty")
    }

    func testOneWorkoutScenario() {
        captureMainScreens(scenario: "one")
    }

    func testManyWorkoutsScenario() {
        captureMainScreens(scenario: "many")
    }

    /// Free tier on the rich dataset — Pro is force-unlocked in DEBUG
    /// simulator builds, so this is the only way to see locked/teaser states.
    func testFreeUserScenario() {
        captureMainScreens(
            scenario: "many",
            extraArguments: ["-UITEST_FORCE_FREE"],
            attachmentPrefix: "free"
        )
    }

    /// The non-rep measurement types in the recorder: the stress scenario's current workout
    /// ends with a duration-typed Plank group (min/sec fields) and a weight+duration
    /// Farmers Carry group — scroll to the bottom and capture them.
    func testRecorderMeasurementTypes() {
        let app = launchApp(
            scenario: "stress",
            extraArguments: ["-UITEST_SHOW_RECORDER", "-UITEST_NO_SHEET"]
        )

        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Recorder never presented")
        waitABit(2)

        let plankHeader = app.staticTexts["Plank"]
        for _ in 0 ..< 12 where !plankHeader.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(plankHeader.waitForExistence(timeout: 5), "Plank group not reachable")
        waitABit(1)
        attach(app, "recorder_duration_and_carry_types")
        app.swipeUp()
        waitABit(1)
        attach(app, "recorder_measurement_types_bottom")

        // The exercise name opens the detail sheet: a duration exercise must show its
        // duration tile (fed by the seeded plank history) instead of weight/e1RM tiles.
        app.staticTexts["Plank"].firstMatch.tap()
        waitABit(3)
        attach(app, "plank_detail_duration_tiles")
    }

    /// Read-only superset pager on a finished workout: the fixture Arm Day starts with a
    /// Biceps Curls + Triceps Extensions superset. Uses the marketing pipeline's
    /// `workoutDetail` deep link, which pushes the detail directly — tapping the History
    /// cell flakily landed on the floating start-workout button instead.
    func testWorkoutDetailSuperset() {
        let app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        app.launchArguments += [
            "-UITEST_FIXTURES",
            "-UITEST_DEEPLINK", "workoutDetail",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        // The superset is Arm Day's first group — visible without scrolling.
        let curlsHeader = app.staticTexts["Biceps Curls"].firstMatch
        XCTAssertTrue(
            curlsHeader.waitForExistence(timeout: 20),
            "Superset group not reachable in workout detail"
        )
        waitABit(2)
        attach(app, "workout_detail_superset")
    }

    /// The containerless superset pager at the end of the stress current workout: page 1
    /// (Incline Bench Press) with its bulge socket and the thread's fork/merge rails, then a
    /// horizontal swipe to the partner page (Barbell Rows) with its own metric badge.
    func testRecorderSupersetPager() {
        let app = launchApp(
            scenario: "stress",
            extraArguments: ["-UITEST_SHOW_RECORDER", "-UITEST_NO_SHEET"]
        )

        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Recorder never presented")
        waitABit(2)

        let rowsHeader = app.staticTexts["Barbell Rows"].firstMatch
        for _ in 0 ..< 14 where !rowsHeader.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(rowsHeader.waitForExistence(timeout: 5), "Superset group not reachable")
        waitABit(1)
        attach(app, "recorder_superset_page1")

        // Swipe the pager itself (a horizontal drag across the card) to the partner page.
        let base = rowsHeader.coordinate(withNormalizedOffset: .zero)
        base.withOffset(CGVector(dx: 240, dy: 90)).press(
            forDuration: 0.05,
            thenDragTo: base.withOffset(CGVector(dx: -80, dy: 90)),
            withVelocity: 800,
            thenHoldForDuration: 0.3
        )
        waitABit(1)
        XCTAssertTrue(
            app.staticTexts["Biceps Curls"].firstMatch.waitForExistence(timeout: 5),
            "Partner page not shown after horizontal swipe"
        )
        attach(app, "recorder_superset_page2")
    }

    // MARK: - Workout recorder (Transmission presentation)
    //
    // Note on element queries: while the persistent exercise tray sheet is
    // presented, everything behind it (the recorder's header, fields, list) is
    // removed from the accessibility tree — UIKit treats the sheet as modal for
    // accessibility even though presentationBackgroundInteraction lets real
    // touches through. That's why -UITEST_NO_SHEET exists (and always has). The
    // tests below therefore split into: element-driven flows without the tray,
    // and coordinate-driven flows with the tray (coordinates need no queries).

    /// Drag mechanics of the Transmission presentation, tray suppressed so the
    /// recorder's own elements stay queryable: keyboard focus, below-threshold
    /// drag snap-back, drag-to-minimize into the pill, reopen from the pill.
    func testRecorderInteractionFlow() {
        let app = launchApp(
            scenario: "stress",
            extraArguments: ["-UITEST_SHOW_RECORDER", "-UITEST_NO_SHEET"]
        )

        // The recorder auto-presents shortly after launch (-UITEST_SHOW_RECORDER).
        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Recorder never presented")
        waitABit(2)
        attach(app, "recorder_01_open")

        // Focus the workout title: keyboard must come up in the presented context.
        nameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard did not appear for title field")
        attach(app, "recorder_02_keyboard")
        app.typeText("\n") // submit (.done) dismisses the keyboard
        waitABit()

        // A short drag (below the 150pt activation threshold) must snap back.
        // Drags start over the muscle chart (top-left) — a neutral header spot;
        // pressing on the title field would begin editing instead.
        let header = app.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.075))
        header.press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.17)),
            withVelocity: 300,
            thenHoldForDuration: 0.3
        )
        waitABit(2)
        XCTAssertTrue(nameField.exists, "Recorder dismissed although the drag stayed below the threshold")
        attach(app, "recorder_03_after_cancelled_drag")

        // A long drag commits the interactive dismissal into the pill. The
        // recorder's own elements can linger as stale accessibility entries
        // right after the dismissal, so the assertion rides on the tab bar
        // becoming reachable again instead.
        header.press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.8)),
            withVelocity: 900,
            thenHoldForDuration: 0.1
        )
        waitABit(2)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar not reachable after drag-to-dismiss — recorder still up?")
        let pill = app.staticTexts["Push Day"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Current-workout pill missing after minimizing")
        attach(app, "recorder_04_minimized_to_pill")

        // Reopen from the pill (tap is how users expand the running workout).
        pill.tap()
        if !nameField.waitForExistence(timeout: 5) {
            // The iOS 26 accessory is known to swallow some synthetic taps; a
            // real-device tap works. Fall back to a coordinate tap before failing.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        }
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Recorder did not reopen from the pill")
        waitABit(2)
        attach(app, "recorder_05_reopened")
    }

    /// Drag-to-dismiss from the set LIST (not just the header): with the tray up,
    /// scroll the list to the top, then drag down from the list body — the recorder
    /// must follow and dismiss into the pill, and plain scrolling must still work.
    func testRecorderListDragDismiss() {
        let app = launchApp(scenario: "stress", extraArguments: ["-UITEST_SHOW_RECORDER"])

        let tray = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Search in Exercises'")
        ).firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 20), "Recorder/tray never presented")
        waitABit(2)

        // Scroll the list to the very top (it opens scrolled to the bottom). Swiping
        // down in the list area moves content down = scrolls up; verifies scrolling
        // still works alongside the dismiss gesture.
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        for _ in 0 ..< 6 {
            mid.press(forDuration: 0.02, thenDragTo: low)
        }
        waitABit(1)
        attach(app, "list_01_scrolled_to_top")

        // Drag down from the list body → dismiss.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86)),
            withVelocity: 700,
            thenHoldForDuration: 0.1
        )
        waitABit(2)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar not reachable — list drag didn't dismiss")
        let pill = app.staticTexts["Push Day"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Current-workout pill missing after list drag-to-dismiss")
        attach(app, "list_02_dismissed_to_pill")
    }

    /// The persistent exercise tray under the Transmission presentation: it must
    /// present only after the morph settles, survive a chrono sheet on top, be
    /// torn down synchronously when the card is dragged, and return after the
    /// recorder is reopened. Driven by coordinates where the tray hides elements.
    func testRecorderTrayLifecycle() {
        let app = launchApp(scenario: "stress", extraArguments: ["-UITEST_SHOW_RECORDER"])

        // Settle-gated tray presentation after the auto-present morph.
        let traySearchField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Search in Exercises'")
        ).firstMatch
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 20), "Exercise tray sheet missing after presentation settled")
        waitABit(2)
        attach(app, "recorder_06_tray_settled")

        // Drag-to-minimize with the tray up: the presentation controller must
        // tear the tray down when the drag commits so the dismissal reaches the
        // recorder. Synthetic drags occasionally fail to engage under simulator
        // load, so allow one retry — the assertion is about the app's behavior
        // once a drag lands, not about XCTest's gesture reliability.
        let trayGone = NSPredicate(format: "exists == false")
        var trayDismissed = false
        // Try neutral header spots: the grabber capsule, the gap left of the
        // close button, and the muscle chart. SwiftUI recognizers under the
        // touch (charts, fields) can starve the dismissal pan, which requires
        // their failure before it begins.
        for originX in [0.42, 0.75, 0.09] where !trayDismissed {
            app.coordinate(withNormalizedOffset: CGVector(dx: originX, dy: 0.075)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: originX, dy: 0.8)),
                withVelocity: 900,
                thenHoldForDuration: 0.1
            )
            let expectation = XCTNSPredicateExpectation(predicate: trayGone, object: traySearchField)
            trayDismissed = XCTWaiter().wait(for: [expectation], timeout: 8) == .completed
        }
        XCTAssertTrue(trayDismissed, "Tray sheet survived the recorder's drag-to-dismiss")
        let pill = app.staticTexts["Push Day"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Current-workout pill missing after minimizing")
        attach(app, "recorder_08_minimized_with_tray_gone")

        // Reopen: the tray has to come back once the morph settles again.
        pill.tap()
        if !traySearchField.waitForExistence(timeout: 5) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        }
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 10), "Tray did not re-present after reopening the recorder")
        waitABit(2)
        attach(app, "recorder_09_reopened_tray_back")

        // Last: the floating timer button (it rides on the tray height) opens
        // the chrono sheet above the tray. Left presented — the test ends here;
        // gesture-dismissing a sheet stacked on the tray is choreography the
        // other flows don't depend on.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.86)).tap()
        // "Timer"/"Stopwatch" are the chrono sheet's mode-switch buttons.
        let timerLabel = app.buttons["Timer"].firstMatch
        XCTAssertTrue(timerLabel.waitForExistence(timeout: 5), "Chrono sheet did not open from the floating timer button")
        waitABit()
        attach(app, "recorder_07_chrono_sheet")
    }

    /// The finish flow on top of the Transmission presentation: close button,
    /// finish-confirmation sheet (it chains off the tray content, so the tray
    /// must be up), and the programmatic dismissal back into the "Start
    /// Workout" pill. The close button sits behind the tray sheet for
    /// accessibility, hence the coordinate tap.
    func testRecorderFinishFlow() {
        let app = launchApp(scenario: "stress", extraArguments: ["-UITEST_SHOW_RECORDER"])

        let traySearchField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Search in Exercises'")
        ).firstMatch
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 20), "Recorder/tray never presented")
        waitABit(2)

        // Close (xmark, top right) → finish confirmation sheet.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.915, dy: 0.105)).tap()
        let endWorkoutButton = app.buttons["End Workout"].firstMatch
        XCTAssertTrue(endWorkoutButton.waitForExistence(timeout: 5), "Finish confirmation sheet did not appear")
        attach(app, "recorder_14_finish_confirmation")

        endWorkoutButton.tap()
        let startPill = app.staticTexts["Start Workout"].firstMatch
        XCTAssertTrue(startPill.waitForExistence(timeout: 8), "Start-workout pill missing after finishing")
        attach(app, "recorder_15_finished_start_pill")
    }

    /// Start pill → WorkoutStartSheet → blank workout: the recorder presentation
    /// has to wait for the start sheet's dismissal (Transmission dismisses it
    /// automatically before presenting). Closing the empty recorder discards the
    /// workout without a confirmation sheet and restores the start pill.
    func testStartWorkoutFlowAndDiscard() {
        let app = launchApp(scenario: "many", extraArguments: ["-UITEST_NO_SHEET"])

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        let startPill = app.staticTexts["Start Workout"].firstMatch
        XCTAssertTrue(startPill.waitForExistence(timeout: 10), "Start-workout pill missing at launch")
        waitABit(2)

        startPill.tap()
        let newWorkoutButton = app.staticTexts["New Workout"].firstMatch
        XCTAssertTrue(newWorkoutButton.waitForExistence(timeout: 5), "Workout start sheet did not open")
        attach(app, "recorder_11_start_sheet")

        newWorkoutButton.tap()
        // Start sheet dismisses, recorder presents on top of its dismissal.
        let closeButton = app.buttons["recorderCloseButton"].firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10), "Recorder did not present from the start sheet")
        waitABit(2)
        attach(app, "recorder_12_new_workout_open")

        // Closing an entry-less workout discards immediately (no confirmation).
        closeButton.tap()
        waitABit(2)
        XCTAssertFalse(closeButton.exists, "Recorder still on screen after discarding the empty workout")
        XCTAssertTrue(startPill.waitForExistence(timeout: 5), "Start pill did not return after discarding")
        attach(app, "recorder_13_discarded_back_to_pill")
    }

    /// The pure user path into the recorder: tapping the current-workout pill
    /// must morph the recorder out of it.
    func testRecorderOpensFromPill() {
        let app = launchApp(scenario: "stress", extraArguments: ["-UITEST_NO_SHEET"])

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        let pill = app.staticTexts["Push Day"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "Current-workout pill missing at launch")
        waitABit(2)
        attach(app, "recorder_16_pill_before_open")

        pill.tap()
        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        if !nameField.waitForExistence(timeout: 5) {
            // Synthetic-tap fallback for the iOS 26 accessory (see fastlane notes).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        }
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Recorder did not open from the pill tap")
        waitABit(2)
        attach(app, "recorder_17_opened_from_pill")
    }

    // MARK: - Walkthrough

    private func captureMainScreens(
        scenario: String,
        extraArguments: [String] = [],
        attachmentPrefix: String? = nil
    ) {
        let app = launchApp(scenario: scenario, extraArguments: extraArguments)
        let prefix = attachmentPrefix ?? scenario

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared for scenario \(scenario)")
        waitABit(2) // let the summary tiles settle

        attach(app, "\(prefix)_01_summary")

        // Visit the other tabs BEFORE any scrolling: a swipe minimizes the
        // tab bar (tabBarMinimizeBehavior) and on short screens (empty
        // scenario) no scroll-up exists to restore it, which would make the
        // History/Templates buttons unreachable.
        tapTab(app, at: 1)
        waitABit()
        attach(app, "\(prefix)_03_history")

        tapTab(app, at: 2)
        waitABit()
        attach(app, "\(prefix)_04_templates")

        tapTab(app, at: 3)
        waitABit()
        attach(app, "\(prefix)_05_search")

        tapTab(app, at: 0)
        waitABit()
        app.swipeUp()
        waitABit()
        attach(app, "\(prefix)_02_summary_scrolled")
    }

    // MARK: - Helpers

    private func launchApp(scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        // Explicit bundle ID because the UI test target has no "Target
        // Application" wiring in the scheme (see LOGITScreenshots.swift).
        let app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        app.launchArguments += [
            "-SCENARIO", scenario,
            // The simulator device may be set to a non-English locale;
            // captures should be deterministic.
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + extraArguments
        app.launch()
        return app
    }

    private func tapTab(_ app: XCUIApplication, at index: Int) {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else { return }
        var buttons = tabBar.buttons.allElementsBoundByIndex
        if index >= buttons.count {
            // Tab bar is minimized after a scroll — swipe down to restore it.
            app.swipeDown()
            sleep(1)
            buttons = tabBar.buttons.allElementsBoundByIndex
        }
        guard index < buttons.count else {
            XCTFail("Tab index \(index) not reachable (\(buttons.count) tab buttons visible)")
            return
        }
        buttons[index].tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitABit(_ seconds: UInt32 = 1) {
        sleep(seconds)
    }
}
