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

    // MARK: - Expandable recorder header

    // The recorder header folds/unfolds on tap (and handle drag): compact workout-cell
    // row ↔ stats panel with progress, session stats, Minimize and Finish. These cover
    // both visual states and the two panel actions. Coordinate-driven where the
    // persistent exercise sheet is up (elements behind sheets are a11y-hidden);
    // element-driven with -UITEST_NO_SHEET where assertions matter.

    /// Visual: collapsed (mid-workout) header, then tap to expand — real persistent sheet up,
    /// so navigation is coordinate-driven (elements behind sheets are a11y-hidden).
    func testHeaderVisualCollapsedThenExpanded() {
        let app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        app.launchArguments += [
            "-UITEST_FIXTURES", "1",
            "-UITEST_SHOW_RECORDER", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        sleep(4)
        attach(app, "hdr_01_collapsed")
        // Tap the caption line ("0:23:06 · 10 Sets") — safely inside the header's
        // tap target, below the status bar and left of the donut.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.081)).tap()
        sleep(2)
        attach(app, "hdr_02_expanded")
        // Tap the caption again to collapse.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.081)).tap()
        sleep(2)
        attach(app, "hdr_03_collapsed_again")
        // Expand once more and tap Finish Workout — the confirmation sheet is hosted
        // inside the persistent exercise sheet, so this only works with the sheet up.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.081)).tap()
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.365)).tap()
        sleep(2)
        attach(app, "hdr_08_finish_confirmation_real")
    }

    /// Visual: brand-new empty workout — header must auto-present expanded.
    func testHeaderVisualEmptyAutoExpanded() {
        let app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        app.launchArguments += [
            "-SCENARIO", "many",
            "-UITEST_START_EMPTY_WORKOUT",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        sleep(5)
        attach(app, "hdr_04_empty_auto_expanded")
    }

    /// Functional: expand via header tap, Finish opens the confirmation sheet.
    func testHeaderFlowExpandAndFinish() {
        let app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        app.launchArguments += [
            "-UITEST_FIXTURES", "1",
            "-UITEST_SHOW_RECORDER", "1",
            "-UITEST_NO_SHEET",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        sleep(4)
        let finishButton = app.buttons["Finish Workout"]
        XCTAssertFalse(finishButton.exists, "Header should start collapsed mid-workout (Finish hidden)")
        // Tap the caption line ("… Sets") — part of the header's tap target.
        let caption = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Sets'")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "Header caption not found")
        caption.tap()
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5), "Finish button should appear when header expands")
        XCTAssertTrue(app.buttons["Minimize"].exists, "Minimize button should appear when header expands")
        attach(app, "hdr_05_expanded_nosheet")
        // Toggle back: tapping the header again must collapse the panel.
        caption.tap()
        sleep(2)
        XCTAssertFalse(finishButton.exists, "Finish button should disappear when header collapses")
        attach(app, "hdr_06_collapsed_after_toggle")
    }

    /// Functional: Minimize dismisses the recorder back to the tab view.
    func testHeaderFlowMinimize() {
        let app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        app.launchArguments += [
            "-UITEST_FIXTURES", "1",
            "-UITEST_SHOW_RECORDER", "1",
            "-UITEST_NO_SHEET",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        sleep(4)
        let caption = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Sets'")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "Header caption not found")
        caption.tap()
        let minimize = app.buttons["Minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 5), "Minimize button should appear when header expands")
        minimize.tap()
        sleep(2)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "Tab bar should be back after minimizing")
        attach(app, "hdr_07_after_minimize")
    }

    // MARK: - Workout recorder (Transmission presentation)
    //
    // Note on element queries: while the persistent exercise tray sheet is
    // presented, everything behind it (the recorder's header, fields, list) is
    // removed from the accessibility tree. -UITEST_NO_SHEET suppresses the tray
    // so those elements stay queryable; tray-up flows are coordinate-driven.
    //
    // Dismissal changed with the expandable header: a header drag now folds/unfolds
    // the stats panel, so the recorder is dismissed by the set-list drag-to-dismiss
    // (at the top) and by the header's Minimize button — not by a header drag.

    /// Keyboard focus in the presented recorder, then Minimize back into the pill, then
    /// reopen. Tray suppressed so the header stays queryable; also proves the title field
    /// still focuses (the header's expand tap is scoped off it onto the caption/handle).
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

        // Focus the workout title: keyboard must come up (and the header's expand tap
        // must NOT steal the tap away from the field).
        nameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard did not appear for title field")
        attach(app, "recorder_02_keyboard")
        app.typeText("\n") // submit (.done) dismisses the keyboard
        waitABit()

        // Expand the header via the caption, then Minimize back into the pill.
        let caption = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Sets'")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "Header caption not found")
        caption.tap()
        let minimize = app.buttons["Minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 5), "Minimize button missing in expanded header")
        minimize.tap()
        waitABit(2)
        let pill = app.staticTexts["Push Day"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 8), "Current-workout pill missing after minimizing")
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

        // Drag down from the list body → dismiss. Starts at 0.55: at the top the
        // header is expanded (scroll-linked, like a large title) and occupies the
        // upper ~45% of the screen, so higher origins would drag the header instead.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
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
    /// torn down synchronously when the recorder is dragged away, and return after
    /// the recorder is reopened. The header now folds/unfolds on a drag, so the
    /// dismissal here comes from the set-list drag-to-dismiss (the path that still
    /// dismisses with the tray up). Coordinate-driven where the tray hides elements.
    func testRecorderTrayLifecycle() {
        let app = launchApp(scenario: "stress", extraArguments: ["-UITEST_SHOW_RECORDER"])

        // Settle-gated tray presentation after the auto-present morph.
        let traySearchField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Search in Exercises'")
        ).firstMatch
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 20), "Exercise tray sheet missing after presentation settled")
        waitABit(2)
        attach(app, "recorder_06_tray_settled")

        // Scroll the list to the very top (it opens scrolled to the bottom) so the
        // list-drag dismissal can engage.
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        for _ in 0 ..< 6 {
            mid.press(forDuration: 0.02, thenDragTo: low)
        }
        waitABit(1)

        // Drag down from the list body: the presentation controller must tear the
        // tray down when the drag commits so the dismissal reaches the recorder.
        // Synthetic drags occasionally fail to engage under simulator load, so allow
        // one retry — the assertion is about the app's behavior once a drag lands.
        let trayGone = NSPredicate(format: "exists == false")
        var trayDismissed = false
        // Origin 0.55: at the top the header is expanded (scroll-linked) and owns
        // the upper part of the screen — higher origins would drag the header.
        for _ in 0 ..< 2 where !trayDismissed {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86)),
                withVelocity: 800,
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

    /// The finish flow on top of the Transmission presentation: expand the header,
    /// tap Finish → finish-confirmation sheet (it chains off the tray content, so
    /// the tray must be up), End Workout → back into the "Start Workout" pill. The
    /// header's expand-tap and Finish button sit behind the tray sheet for
    /// accessibility, hence the coordinate taps.
    func testRecorderFinishFlow() {
        let app = launchApp(scenario: "stress", extraArguments: ["-UITEST_SHOW_RECORDER"])

        let traySearchField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Search in Exercises'")
        ).firstMatch
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 20), "Recorder/tray never presented")
        waitABit(2)

        // Expand the header (caption tap), then Finish (bottom-right of the panel)
        // → finish confirmation sheet.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.081)).tap()
        waitABit(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.365)).tap()
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
    /// automatically before presenting). The empty workout auto-expands the header,
    /// so Finish discards the entry-less workout with no confirmation and restores
    /// the start pill.
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
        // Start sheet dismisses, recorder presents empty → header auto-expanded, so
        // the Finish button is on screen.
        let finish = app.buttons["Finish Workout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "Recorder did not present from the start sheet")
        waitABit(2)
        attach(app, "recorder_12_new_workout_open")

        // Finishing an entry-less workout discards it immediately (no confirmation).
        finish.tap()
        waitABit(2)
        XCTAssertFalse(finish.exists, "Recorder still on screen after discarding the empty workout")
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
