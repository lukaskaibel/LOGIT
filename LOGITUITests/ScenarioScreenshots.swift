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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.383)).tap()
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
