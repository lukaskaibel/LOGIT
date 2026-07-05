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
