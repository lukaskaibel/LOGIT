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

    // MARK: - Summary nav bar (accessibility regression)

    /// Regression guard for the Summary's in-flow large-title row. The weekly-goal count
    /// pill sits in that row where the settings avatar used to; both are in-flow scroll
    /// content rather than `ToolbarItem(placement: .largeTitle)` content, because iOS 26
    /// never exposes that placement's custom content to accessibility (the navigation bar
    /// reports zero children) and the control would be unreachable. Asserts the pill is
    /// reachable by identifier and opens the goal screen, that Settings is still reachable
    /// now that it is a tab rather than a sheet, and that hiding the Summary's navigation
    /// bar does not leak into pushed detail screens.
    func testSummaryNavigationBarAccessible() {
        let app = launchApp(scenario: "many")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        waitABit(2)

        let goalPill = app.buttons["weeklyGoalPill"]
        XCTAssertTrue(
            goalPill.waitForExistence(timeout: 5),
            "weeklyGoalPill not reachable in the accessibility tree on Summary"
        )
        goalPill.tap()
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Weekly goal pill did not push the goal screen")
        backButton.tap()
        waitABit(1)

        // Settings moved out of the Summary into its own tab.
        tapTab(app, at: 3)
        waitABit(1)
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "Settings tab did not show the Settings screen"
        )
        tapTab(app, at: 0)
        waitABit(1)

        // A stat tile must still push a screen whose navigation bar (back button) works.
        let volume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Volume'")).firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 5), "Volume tile missing")
        volume.tap()
        let detailBack = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(detailBack.waitForExistence(timeout: 5), "Detail screen has no navigation bar / back button")
    }

    // MARK: - Personal records (per-exercise cards)

    /// The records surfaces after the per-exercise regrouping (one card/row/count per exercise,
    /// the most tangible metric leading, sibling records folded into the card): captures the
    /// workout detail's records tile and the records screen, then asserts a record card pushes
    /// the exercise detail screen — the card's whole surface is a NavigationLink now.
    func testWorkoutRecordsScreens() {
        let app = launchApp(scenario: "many")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        waitABit(2)

        // History → the newest workout whose cell advertises records ("· n PR").
        tapTab(app, at: 1)
        waitABit()
        let prCell = app.buttons.matching(NSPredicate(format: "label CONTAINS ' PR'")).firstMatch
        XCTAssertTrue(prCell.waitForExistence(timeout: 5), "No workout cell advertising PRs in the many scenario")
        prCell.tap()
        waitABit()

        // The records tile sits below the stat grid — bring it on screen.
        let recordsTile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Personal Records'")).firstMatch
        for _ in 0 ..< 3 where !(recordsTile.exists && recordsTile.isHittable) {
            app.swipeUp()
            waitABit()
        }
        attach(app, "records_01_workout_detail_tile")
        XCTAssertTrue(recordsTile.waitForExistence(timeout: 5), "Records tile missing on the workout detail")
        recordsTile.tap()
        waitABit()
        attach(app, "records_02_records_screen")

        // A record card is a button into the exercise detail screen.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'New Record'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "No record card on the records screen")
        card.tap()
        let cardBackButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(cardBackButton.waitForExistence(timeout: 5), "Record card did not push the exercise detail screen")
        waitABit(1)
        attach(app, "records_03_exercise_detail_from_card")
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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.27)).tap()
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
        let finishButton = app.buttons["Finish"]
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

    /// A short list (one exercise) via the real start flow: the set list must run to the
    /// bottom edge under the tray, so the card's Add Set row stays fully on-screen instead
    /// of being clipped mid-screen (regression for the in-flow header's bottom inset).
    func testShortWorkoutBottomEdge() {
        let app = XCUIApplication(bundleIdentifier: ".com.lukaskbl.LOGIT")
        app.launchArguments += [
            "-SCENARIO", "many",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        let startPill = app.staticTexts["Start Workout"].firstMatch
        XCTAssertTrue(startPill.waitForExistence(timeout: 25), "Start-workout pill missing")
        startPill.tap()
        let newWorkout = app.staticTexts["New Workout"].firstMatch
        XCTAssertTrue(newWorkout.waitForExistence(timeout: 6), "New Workout entry missing")
        newWorkout.tap()
        sleep(3)
        // Add one exercise from the tray → a list far shorter than the viewport.
        let exercise = app.staticTexts["Ab Wheel Rollout"].firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 10), "Exercise tray missing")
        exercise.tap()
        sleep(2)
        let addSet = app.buttons["Add Set"].firstMatch

        // Two sets first: the card must stay COMPACT. The scroll slack a short list is given
        // is travel to scroll into, not height to grow into — the set rows sit one after
        // another whatever the viewport has left over. Checked at two sets because the slack
        // is split between the rows, so this is where a stretching card is most obvious (a
        // regression from an unpinned swipe-to-delete row drew them ~150pt apart here).
        XCTAssertTrue(addSet.exists, "Add Set button missing")
        addSet.tap()
        sleep(1)
        let firstRow = app.staticTexts["1"].firstMatch
        let secondRow = app.staticTexts["2"].firstMatch
        XCTAssertTrue(firstRow.exists && secondRow.exists, "Set-index labels missing")
        let rowPitch = secondRow.frame.minY - firstRow.frame.minY
        XCTAssertLessThan(
            rowPitch,
            100,
            "Set rows are \(rowPitch)pt apart — the card is stretching to fill the viewport instead of staying compact"
        )

        // Grow the list to ~6 sets (the reported case): the card's Add Set row must not
        // be clipped and the card should run to the bottom edge under the tray.
        for _ in 0 ..< 4 where addSet.exists { addSet.tap() }
        sleep(2)
        attach(app, "short_bottom")
        // The Add Set row (bottom of the only card) must be fully on-screen, not clipped
        // off the bottom edge — the whole point of the fix.
        XCTAssertTrue(addSet.isHittable, "Add Set row is clipped — the short list isn't running to the bottom edge")
    }

    /// The non-rep measurement types in the recorder: the stress scenario's current workout
    /// carries a duration-typed Plank group (min/sec fields) and a weight+duration
    /// Farmer's Walk group — scroll each into view and capture it.
    func testRecorderMeasurementTypes() {
        let app = launchApp(
            scenario: "stress",
            // -UITEST_NO_SCROLLTO: park the list at the top and keep it there, so
            // scrollRecorder's drags aren't undone by the recorder's own auto-scrolls.
            extraArguments: ["-UITEST_SHOW_RECORDER", "-UITEST_NO_SHEET", "-UITEST_NO_SCROLLTO"]
        )

        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Recorder never presented")
        waitABit(2)

        XCTAssertTrue(
            scrollRecorder(app, toGroup: "Plank"),
            "Plank group not reachable"
        )
        waitABit(1)
        attach(app, "recorder_duration_and_carry_types")
        // One group further down: the weight+duration carry. It renders under its
        // default-library name ("Farmer's Walk"), not TestScenarios' fallback string —
        // the fixture only falls back to that when the library isn't loaded.
        XCTAssertTrue(
            scrollRecorder(app, toGroup: "Farmer's Walk"),
            "Farmer's Walk group not reachable"
        )
        waitABit(1)
        attach(app, "recorder_measurement_types_bottom")

        // The exercise name opens the detail sheet: a duration exercise must show its
        // duration tile (fed by the seeded plank history) instead of weight/e1RM tiles.
        // Back up to Plank first — the carry scroll left its header above the fold.
        XCTAssertTrue(
            scrollRecorder(app, toGroup: "Plank"),
            "Plank group not reachable for the detail tap"
        )
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

    /// Template parity (see AGENT.md, "Templates mirror workouts"): the template detail and
    /// editor must render set groups exactly like the workout side — index bulges, the thread
    /// between groups, and a superset as the containerless per-exercise pager. The preview Push
    /// Day template ends with a Triceps Extensions + Lateral Raises superset.
    func testTemplateEditorSuperset() {
        let app = launchApp(scenario: "many")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")

        tapTab(app, at: 2)
        waitABit(2)
        attach(app, "template_01_list")

        // The list holds both the shipped default templates (subtitled with a description) and
        // the preview ones (subtitled with their exercise names) — and both sets contain a
        // "Push Day". Match the preview one by an exercise only it lists.
        let previewPush = app.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Triceps Extensions'")).firstMatch
        for _ in 0 ..< 12 where !(previewPush.exists && previewPush.isHittable) {
            app.swipeUp()
            waitABit()
        }
        XCTAssertTrue(previewPush.waitForExistence(timeout: 5), "Preview Push Day template missing")
        previewPush.tap()
        waitABit(2)

        // Detail: scroll to the superset finisher at the end of the exercise list.
        let tricepsHeader = app.staticTexts["Triceps Extensions"].firstMatch
        for _ in 0 ..< 12 where !(tricepsHeader.exists && tricepsHeader.isHittable) {
            app.swipeUp()
            waitABit()
        }
        XCTAssertTrue(
            tricepsHeader.waitForExistence(timeout: 5),
            "Superset group not reachable in template detail"
        )
        attach(app, "template_02_detail_superset")

        // Swipe the pager to the partner page — same gesture as the recorder's.
        let base = tricepsHeader.coordinate(withNormalizedOffset: .zero)
        base.withOffset(CGVector(dx: 240, dy: 90)).press(
            forDuration: 0.05,
            thenDragTo: base.withOffset(CGVector(dx: -80, dy: 90)),
            withVelocity: 800,
            thenHoldForDuration: 0.3
        )
        waitABit(1)
        XCTAssertTrue(
            app.staticTexts["Lateral Raises"].firstMatch.waitForExistence(timeout: 5),
            "Partner page not shown after horizontal swipe in template detail"
        )
        attach(app, "template_03_detail_superset_page2")

        // Editor: the same layout with the edit controls, opened from the detail's ⋯ menu.
        let menuButton = app.navigationBars.buttons.element(boundBy: 1)
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "Template detail toolbar menu missing")
        menuButton.tap()
        waitABit(1)
        let editButton = app.buttons["Edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Edit not offered in the template menu")
        editButton.tap()
        waitABit(3)

        let editorTriceps = app.staticTexts["Triceps Extensions"].firstMatch
        for _ in 0 ..< 12 where !(editorTriceps.exists && editorTriceps.isHittable) {
            app.swipeUp()
            waitABit()
        }
        XCTAssertTrue(
            editorTriceps.waitForExistence(timeout: 5),
            "Superset group not reachable in the template editor"
        )
        attach(app, "template_04_editor_superset")
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
        XCTAssertTrue(
            scrollRecorder(app, toGroup: "Barbell Rows"),
            "Superset group not reachable"
        )
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

    /// The distance measurement types in the recorder: the stress scenario's current
    /// workout ends with a distance+duration Running group (km + sec fields) and a
    /// weight+distance Sled Push group (kg + m fields). Scroll to them, capture, then
    /// open the running detail: a distance exercise must show its distance tile (fed by
    /// the seeded treadmill history) instead of weight/e1RM tiles.
    func testRecorderDistanceTypes() {
        let app = launchApp(
            scenario: "stress",
            extraArguments: ["-UITEST_SHOW_RECORDER", "-UITEST_NO_SHEET", "-UITEST_NO_SCROLLTO"]
        )

        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Recorder never presented")
        waitABit(2)

        XCTAssertTrue(
            scrollRecorder(app, toGroup: "Sled Push"),
            "Sled Push group not reachable"
        )
        waitABit(1)
        attach(app, "recorder_distance_types")

        // Running sits one group above the sled, so bring it back into view before tapping
        // its name — the sled scroll leaves it above the fold.
        XCTAssertTrue(
            scrollRecorder(app, toGroup: "Running"),
            "Running group not reachable"
        )
        app.staticTexts["Running"].firstMatch.tap()
        waitABit(3)
        attach(app, "running_detail_distance_tiles")
    }

    /// The per-exercise distance unit choice, end to end: long-press a Sled Push set →
    /// Measurement submenu → the Distance Unit section appears → switch to kilometers → the
    /// row re-renders its 20 m as 0.02 km. Values are stored in meters, so this is purely a
    /// display flip.
    func testDistanceUnitChoiceMenu() {
        let app = launchApp(
            scenario: "stress",
            extraArguments: ["-UITEST_SHOW_RECORDER", "-UITEST_NO_SHEET", "-UITEST_NO_SCROLLTO"]
        )

        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Recorder never presented")
        waitABit(2)

        let sledHeader = app.staticTexts["Sled Push"].firstMatch
        XCTAssertTrue(
            scrollRecorder(app, toGroup: "Sled Push"),
            "Sled Push group not reachable"
        )
        waitABit(1)

        // Long-press one of the sled's set rows to open its context menu.
        let measurementItem = app.buttons["Measurement"].firstMatch
        XCTAssertTrue(
            openSetContextMenu(underHeader: sledHeader, probe: measurementItem),
            "Set context menu did not open on the sled set"
        )
        measurementItem.tap()

        let kilometersOption = app.buttons["Kilometers (km)"].firstMatch
        XCTAssertTrue(
            kilometersOption.waitForExistence(timeout: 4),
            "Distance Unit options missing from the Measurement menu"
        )
        attach(app, "measurement_menu_distance_unit")

        // The submenu holds all seven types plus the unit section; give its presentation a
        // few beats to settle before tapping (don't swipe here — a swipe over an open menu
        // dismisses it rather than scrolling it).
        var tappedKilometers = false
        for _ in 0 ..< 4 where !tappedKilometers {
            if kilometersOption.exists, kilometersOption.isHittable {
                kilometersOption.tap()
                tappedKilometers = true
            } else {
                waitABit(1)
            }
        }
        XCTAssertTrue(tappedKilometers, "Kilometers option never became tappable in the menu")
        waitABit(1)
        // The distance value lives in the entry's text field (20 m = 0.02 km).
        let kmField = app.textFields.matching(NSPredicate(format: "value == '0.02'")).firstMatch
        XCTAssertTrue(
            kmField.waitForExistence(timeout: 4),
            "Sled distance did not re-render as kilometers after the unit switch"
        )
        attach(app, "sled_row_in_kilometers")
    }

    /// The exercise detail's distance adaptation, reached through the Exercises tab (the
    /// recorder's name-tap detail sheet is suppressed under -UITEST_NO_SHEET, so this is the
    /// reliable element-driven route): Running must show the distance + duration tiles fed by
    /// the seeded treadmill history, and the distance tile must open its chart screen.
    func testDistanceExerciseDetailFromList() {
        let app = launchApp(scenario: "stress")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        tapTab(app, at: 4)
        waitABit(1)

        // The Search tab is a hub; go through its Exercises list. Prefer the list's search
        // field when one is exposed; otherwise swipe down the alphabetical list to R.
        let exercisesRow = app.staticTexts["Exercises"].firstMatch
        XCTAssertTrue(exercisesRow.waitForExistence(timeout: 5), "Exercises row missing on the Search tab")
        exercisesRow.tap()
        waitABit(2)

        let runningRow = app.staticTexts["Running"].firstMatch
        let listSearchField = app.textFields.firstMatch
        if listSearchField.waitForExistence(timeout: 2) {
            listSearchField.tap()
            app.typeText("Running")
            waitABit(2)
        } else {
            for _ in 0 ..< 30 where !runningRow.isHittable {
                app.swipeUp()
            }
        }
        XCTAssertTrue(runningRow.waitForExistence(timeout: 5), "Running not reachable in the exercise list")
        runningRow.tap()
        waitABit(3)
        attach(app, "running_detail_from_list")

        let distanceTile = app.staticTexts["Distance"].firstMatch
        XCTAssertTrue(distanceTile.waitForExistence(timeout: 5), "Distance tile missing on a distance exercise")
        distanceTile.tap()
        waitABit(2)
        attach(app, "running_distance_chart_screen")
    }

    // MARK: - Workout recorder (Transmission presentation)
    //
    // Note on element queries: while the persistent exercise tray sheet is
    // presented, everything behind it (the recorder's header, fields, list) is
    // removed from the accessibility tree. -UITEST_NO_SHEET suppresses the tray
    // so those elements stay queryable; tray-up flows are coordinate-driven.
    //
    // Dismissal: a header drag folds/unfolds the stats panel, so the recorder is
    // dismissed by the set-list drag-to-dismiss (at the top), by pulling on a header
    // that is already fully extended, and by the header's Minimize button. All drag
    // paths only engage past a deliberate distance — a swipe never minimizes.

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
        // still works alongside the dismiss gesture. Each swipe stays well under the
        // dismissal's engagement distance — scrolling back to the top must never
        // minimize the recorder.
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
        for _ in 0 ..< 10 {
            mid.press(forDuration: 0.02, thenDragTo: low)
        }
        waitABit(1)
        attach(app, "list_01_scrolled_to_top")
        XCTAssertTrue(tray.exists, "Scrolling the list back to its top must not minimize the recorder")

        // Drag down from the list body → dismiss. Starts at 0.55: at the top the
        // header is expanded (scroll-linked, like a large title) and occupies the
        // upper ~45% of the screen, so higher origins would drag the header instead.
        // The travel (~0.35 of the screen) clears the engagement distance a mere
        // swipe never reaches.
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
        // list-drag dismissal can engage. Short swipes: anything past the engagement
        // distance would minimize the recorder before the drag under test.
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
        for _ in 0 ..< 10 {
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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.27)).tap()
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
        let finish = app.buttons["Finish"]
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

    // MARK: - Template editor tray: nested Create Exercise sheet

    /// A sheet presented from INSIDE the editors' background-interactive exercise tray
    /// must survive: while the tray passes touches through, UIKit and SwiftUI fight over
    /// a stacked sheet (the tray is dismissed and re-presented, tearing the nested sheet
    /// down within seconds). The rest/reorder sheets are guarded in the editors
    /// themselves; this covers ExerciseSelectionScreen's own Create Exercise sheet,
    /// whose state the editors can't see directly.
    func testTemplateEditorCreateExerciseSheetStaysUp() {
        let app = launchApp(scenario: "many")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        tapTab(app, at: 2)
        waitABit(1)

        // "+" toolbar menu → New Template → the editor opens with its persistent tray.
        let plusButton = app.navigationBars.buttons["Add"].firstMatch
        XCTAssertTrue(plusButton.waitForExistence(timeout: 5), "Templates + button missing")
        plusButton.tap()
        let newTemplateItem = app.buttons["New Template"].firstMatch
        XCTAssertTrue(newTemplateItem.waitForExistence(timeout: 5), "New Template menu item missing")
        newTemplateItem.tap()

        let traySearchField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Search in Exercises'")
        ).firstMatch
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 10), "Template editor tray missing")
        waitABit(2)

        // The + next to the search field — ExerciseSelectionScreen's own Create
        // Exercise sheet. (No typing: focusing the tray search field is flaky with a
        // connected hardware keyboard, and the + presents the same sheet either way.)
        let addExercise = app.buttons["Add"].firstMatch
        XCTAssertTrue(addExercise.waitForExistence(timeout: 5), "Tray + (create exercise) button missing")
        addExercise.tap()

        let newExerciseTitle = app.staticTexts["New Exercise"].firstMatch
        XCTAssertTrue(newExerciseTitle.waitForExistence(timeout: 5), "Create Exercise sheet never presented")
        attach(app, "tray_create_01_presented")

        // The sheet must stay up — on the unguarded build the tray fight tears it
        // down within a few seconds.
        var vanishedAfter: Int?
        for second in 1 ... 6 {
            waitABit(1)
            if !newExerciseTitle.exists {
                vanishedAfter = second
                break
            }
        }
        attach(app, "tray_create_02_after_wait")
        XCTAssertNil(
            vanishedAfter,
            "Create Exercise sheet vanished after ~\(vanishedAfter ?? 0)s — tray dismiss/re-present fight"
        )
        guard vanishedAfter == nil else { return }

        // Cancel must dismiss it cleanly, the tray must come back, and the sheet must
        // be reopenable (an abnormal teardown leaves the sheet binding stuck non-nil,
        // blocking every later attempt). Scope the query to the create sheet's own
        // navigation bar — a bare buttons["Cancel"].firstMatch can resolve to the
        // editor's (occluded) Cancel and the tap then lands on the scrim.
        let sheetCancel = app.navigationBars["New Exercise"].buttons["Cancel"].firstMatch
        XCTAssertTrue(sheetCancel.waitForExistence(timeout: 3), "Create sheet's Cancel button not found")
        sheetCancel.tap()
        waitABit(2)
        XCTAssertFalse(newExerciseTitle.exists, "Create Exercise sheet stuck after Cancel")
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 5), "Tray gone after closing the create sheet")
        addExercise.tap()
        XCTAssertTrue(
            newExerciseTitle.waitForExistence(timeout: 5),
            "Create Exercise sheet could not be reopened — stuck sheet binding"
        )
        attach(app, "tray_create_03_reopened")
    }

    /// Same guarantee for the workout editor's tray (History → + → editor): its
    /// Create Exercise sheet is host-owned for the same reason as the template
    /// editor's — see `testTemplateEditorCreateExerciseSheetStaysUp`.
    func testWorkoutEditorCreateExerciseSheetStaysUp() {
        let app = launchApp(scenario: "many")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        tapTab(app, at: 1)
        waitABit(1)

        let plusButton = app.navigationBars.buttons["Add"].firstMatch
        XCTAssertTrue(plusButton.waitForExistence(timeout: 5), "History + button missing")
        plusButton.tap()

        let traySearchField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Search in Exercises'")
        ).firstMatch
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 10), "Workout editor tray missing")
        waitABit(2)

        let addExercise = app.buttons["Add"].firstMatch
        XCTAssertTrue(addExercise.waitForExistence(timeout: 5), "Tray + (create exercise) button missing")
        addExercise.tap()

        let newExerciseTitle = app.staticTexts["New Exercise"].firstMatch
        XCTAssertTrue(newExerciseTitle.waitForExistence(timeout: 5), "Create Exercise sheet never presented")

        var vanishedAfter: Int?
        for second in 1 ... 6 {
            waitABit(1)
            if !newExerciseTitle.exists {
                vanishedAfter = second
                break
            }
        }
        attach(app, "workout_tray_create_after_wait")
        XCTAssertNil(
            vanishedAfter,
            "Create Exercise sheet vanished after ~\(vanishedAfter ?? 0)s — tray dismiss/re-present fight"
        )
        guard vanishedAfter == nil else { return }

        let sheetCancel = app.navigationBars["New Exercise"].buttons["Cancel"].firstMatch
        XCTAssertTrue(sheetCancel.waitForExistence(timeout: 3), "Create sheet's Cancel button not found")
        sheetCancel.tap()
        waitABit(2)
        XCTAssertFalse(newExerciseTitle.exists, "Create Exercise sheet stuck after Cancel")
        XCTAssertTrue(traySearchField.waitForExistence(timeout: 5), "Tray gone after closing the create sheet")
        addExercise.tap()
        XCTAssertTrue(
            newExerciseTitle.waitForExistence(timeout: 5),
            "Create Exercise sheet could not be reopened — stuck sheet binding"
        )
        attach(app, "workout_tray_create_reopened")
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
        attach(app, "\(prefix)_05_settings")

        tapTab(app, at: 4)
        waitABit()
        attach(app, "\(prefix)_06_search")

        tapTab(app, at: 0)
        waitABit()
        app.swipeUp()
        waitABit()
        attach(app, "\(prefix)_02_summary_scrolled")
    }

    // MARK: - Exercise editor (measurement builder)

    /// The redesigned exercise editor: measurement type is composed from four tracked-field
    /// chips with a live set preview, instead of the old seven-option dropdown. Drives the
    /// full chip state machine — the two-field cap disabling chips, the only two reachable
    /// incomplete selections (nothing, weight alone) disabling Save with a hint — then saves
    /// a weight+distance exercise and confirms it landed in the list.
    func testExerciseBuilderCreateFlow() {
        let app = launchApp(scenario: "many")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        waitABit(1)
        tapTab(app, at: 4)
        waitABit(1)

        let exercisesRow = app.staticTexts["Exercises"].firstMatch
        XCTAssertTrue(exercisesRow.waitForExistence(timeout: 5), "Exercises row missing on the Search tab")
        exercisesRow.tap()
        waitABit(1)

        app.buttons["addExerciseButton"].firstMatch.tap()

        let repsChip = app.buttons["trackedFieldChip_repetitions"]
        let weightChip = app.buttons["trackedFieldChip_weight"]
        let durationChip = app.buttons["trackedFieldChip_duration"]
        let distanceChip = app.buttons["trackedFieldChip_distance"]
        XCTAssertTrue(repsChip.waitForExistence(timeout: 5), "Builder chips missing on the editor")

        // The name field autofocuses; name the exercise and dismiss the keyboard via return
        // so the lower chips and preview stay hittable.
        app.typeText("UITest Carry\n")
        waitABit(1)
        attach(app, "exercise_builder_new_default")

        // Default Reps & Weight: the two-field cap disables the other chips.
        XCTAssertFalse(durationChip.isEnabled, "Duration chip enabled despite two fields selected")
        XCTAssertFalse(distanceChip.isEnabled, "Distance chip enabled despite two fields selected")
        XCTAssertTrue(
            app.descendants(matching: .any)["setPreviewTile"].exists,
            "Set preview missing for a valid selection"
        )

        let saveButton = app.buttons["Save"].firstMatch

        // Reps alone is a valid type; duration cannot join reps.
        weightChip.tap()
        waitABit(1)
        XCTAssertFalse(durationChip.isEnabled, "Duration chip must not pair with reps")
        XCTAssertTrue(saveButton.isEnabled, "Reps-only must be saveable")

        // Empty selection: Save disabled, hint shown.
        repsChip.tap()
        waitABit(1)
        XCTAssertFalse(saveButton.isEnabled, "Save enabled with nothing selected")
        attach(app, "exercise_builder_empty_hint")

        // Weight alone is incomplete: still no Save, partner hint shown.
        weightChip.tap()
        waitABit(1)
        XCTAssertFalse(saveButton.isEnabled, "Save enabled with weight alone")

        // Weight + distance: valid again — preview with the distance unit switch appears.
        distanceChip.tap()
        waitABit(1)
        XCTAssertTrue(saveButton.isEnabled, "Save disabled for weight + distance")
        // The segmented control swallows its SwiftUI identifier, so assert via its segments.
        XCTAssertTrue(
            app.buttons["km"].waitForExistence(timeout: 3) && app.buttons["m"].exists,
            "Distance unit switch missing for a distance type"
        )
        attach(app, "exercise_builder_weight_distance")

        saveButton.tap()
        waitABit(2)

        // The alphabetical list is lazy and huge — reach the U-named row through search;
        // repeated snapshot-and-swipe loops time out the accessibility queries here.
        let searchField = app.searchFields.firstMatch
        if !searchField.waitForExistence(timeout: 3) {
            app.buttons["Search"].firstMatch.tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Exercise list search never opened")
        }
        searchField.tap()
        app.typeText("UITest Carry")
        waitABit(2)
        XCTAssertTrue(
            app.staticTexts["UITest Carry"].firstMatch.waitForExistence(timeout: 5),
            "Saved exercise not in the list"
        )
        attach(app, "exercise_builder_saved_in_list")
    }

    /// Editing an existing exercise: the builder must arrive prefilled from the exercise's
    /// measurement type, and changing the type must surface the history-safety footnote.
    /// Default exercises can't be edited, so the flow first creates a duration-only exercise,
    /// then reopens it through detail → menu → Edit.
    func testExerciseBuilderEditExistingFlow() {
        let app = launchApp(scenario: "many")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        waitABit(1)
        tapTab(app, at: 4)
        waitABit(1)

        let exercisesRow = app.staticTexts["Exercises"].firstMatch
        XCTAssertTrue(exercisesRow.waitForExistence(timeout: 5), "Exercises row missing on the Search tab")
        exercisesRow.tap()
        waitABit(1)

        app.buttons["addExerciseButton"].firstMatch.tap()

        let repsChip = app.buttons["trackedFieldChip_repetitions"]
        let weightChip = app.buttons["trackedFieldChip_weight"]
        let durationChip = app.buttons["trackedFieldChip_duration"]
        XCTAssertTrue(repsChip.waitForExistence(timeout: 5), "Builder chips missing on the editor")

        // Compose a duration-only exercise: drop reps and weight, add duration.
        app.typeText("UITest Plank\n")
        waitABit(1)
        repsChip.tap()
        weightChip.tap()
        durationChip.tap()
        waitABit(1)
        app.buttons["Save"].firstMatch.tap()
        waitABit(2)

        // Reach the new exercise through search — repeatedly snapshotting the full
        // alphabetical list while swiping times out the accessibility queries.
        let searchField = app.searchFields.firstMatch
        if !searchField.waitForExistence(timeout: 3) {
            app.buttons["Search"].firstMatch.tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Exercise list search never opened")
        }
        searchField.tap()
        app.typeText("UITest Plank")
        waitABit(2)

        let savedRow = app.staticTexts["UITest Plank"].firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 5), "Created exercise not found via search")
        savedRow.tap()
        waitABit(3) // charts on the detail screen need a moment before heavy queries

        let detailMenu = app.buttons["exerciseDetailMenu"].firstMatch
        XCTAssertTrue(detailMenu.waitForExistence(timeout: 10), "Detail screen never opened")
        detailMenu.tap()
        let editItem = app.buttons["Edit"].firstMatch
        XCTAssertTrue(editItem.waitForExistence(timeout: 3), "Edit item missing from the detail menu")
        editItem.tap()
        waitABit(1)

        // The builder arrives prefilled: duration on, reps unpairable, weight addable.
        XCTAssertTrue(durationChip.waitForExistence(timeout: 5), "Builder chips missing when editing")
        XCTAssertTrue(durationChip.isSelected, "Duration chip not prefilled from the exercise")
        XCTAssertFalse(repsChip.isEnabled, "Reps chip must not pair with duration")
        XCTAssertTrue(weightChip.isEnabled, "Weight chip must be addable to duration")
        attach(app, "exercise_builder_edit_prefilled")

        // Changing the type shows the history-safety footnote.
        weightChip.tap()
        waitABit(1)
        XCTAssertTrue(
            app.staticTexts["Existing sets keep the values they were recorded with. Only new sets use the new measurement."]
                .waitForExistence(timeout: 3),
            "Type-change footnote missing after changing the measurement"
        )
        attach(app, "exercise_builder_edit_type_changed")

        app.buttons["Save"].firstMatch.tap()
        waitABit(2)
        XCTAssertTrue(
            app.staticTexts["UITest Plank"].firstMatch.waitForExistence(timeout: 5),
            "Detail screen not visible after saving the edit"
        )
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

    /// Tab titles as they appear in English (the tests launch with -AppleLanguages (en)).
    /// In bar order. Settings became a tab when This Week / Progress merged into one
    /// Summary and the profile avatar left the screen, so Search sits at 4 now.
    private static let tabLabels = ["Summary", "History", "Templates", "Settings", "Search"]

    private func tapTab(_ app: XCUIApplication, at index: Int) {
        let label = Self.tabLabels[index]
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else { return }

        // Look up by label, never by index: on iOS 26 the bar collapses both
        // after a scroll (tabBarMinimizeBehavior) and while the Search tab is
        // active (the regular tabs fold into a single leading button next to
        // the search pill), and in those states positional indices lie.
        var button = tabBar.buttons[label]
        if !button.exists {
            // Scroll-minimized bar: swiping down restores it.
            app.swipeDown()
            sleep(1)
            button = tabBar.buttons[label]
        }
        if !button.exists, tabBar.buttons.count > 0 {
            // Search-active bar: tapping the collapsed leading button leaves
            // search and re-expands the full tab row.
            tabBar.buttons.firstMatch.tap()
            sleep(1)
            button = tabBar.buttons[label]
        }
        guard button.waitForExistence(timeout: 2) else {
            XCTFail("Tab '\(label)' not reachable in the tab bar")
            return
        }
        button.tap()
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

    /// Scrolls the recorder's set list until the `name` set-group header rests in a band
    /// where the group's own set rows sit on-screen below it, and reports whether it got
    /// there. Callers should launch with `-UITEST_NO_SCROLLTO` (see below).
    ///
    /// Two things make this harder than "swipe until you see it", and both cost real
    /// debugging time when ignored:
    ///
    /// 1. **Direction isn't obvious.** Left to itself the recorder auto-scrolls to the
    ///    *bottom* of the list on appear, so a group in the middle of a long workout starts
    ///    *above* the viewport and `swipeUp()` — the reflex — is a no-op against the bottom
    ///    stop. That is exactly how #103 broke three tests here: it appended a superset and
    ///    a closing group *after* their targets, the targets slid above the fold, and no
    ///    number of upward swipes could ever bring them back. So take the direction from
    ///    where the header actually is, and flip if half the budget turns up nothing.
    /// 2. **The list scrolls itself.** Focusing a set field sends the list back to the
    ///    bottom, and a drag landing on a value field focuses one — so a drag can silently
    ///    undo itself. Hence `-UITEST_NO_SCROLLTO` at the caller (it switches off both the
    ///    on-appear and the on-focus auto-scroll) and `dx: 0.12` here, which keeps the drag
    ///    in the set-number column, clear of every field.
    ///
    /// Position is judged by frame, never by `isHittable`: the recorder draws its own header
    /// and a fade mask over the list, and `isHittable` comes back false for headers that are
    /// plainly on screen. Steering on it made this walk straight past its target to the end
    /// of the list and back again.
    ///
    /// Controlled drags rather than `swipeUp()`/`swipeDown()`: a momentum flick overshoots
    /// the band and oscillates around it. Each step is shorter than the band is tall, so a
    /// step can't hop over the target.
    @discardableResult
    private func scrollRecorder(
        _ app: XCUIApplication,
        toGroup name: String,
        maxSteps: Int = 14
    ) -> Bool {
        let header = app.staticTexts[name].firstMatch
        let height = app.frame.height
        // Clear of the recorder's in-flow header at the top, high enough that the group's
        // set rows are still on-screen underneath.
        let bandTop = height * 0.10
        let bandBottom = height * 0.55
        // Walk down the list first: with -UITEST_NO_SCROLLTO the list rests at the top, where
        // every group is below — and where a downward drag would latch the recorder's
        // drag-to-dismiss instead of scrolling.
        var goingDownTheList = true

        for step in 0 ..< maxSteps {
            if let frame = onScreenFrame(of: header, in: app) {
                if frame.midY >= bandTop, frame.midY <= bandBottom { return true }
                goingDownTheList = frame.midY > bandBottom
            } else if step == maxSteps / 2 {
                // Never surfaced walking one way — the fixture must have moved it.
                goingDownTheList.toggle()
            }
            let fromY = goingDownTheList ? 0.62 : 0.32
            let toY = goingDownTheList ? 0.32 : 0.62
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: fromY))
                .press(
                    forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: toY))
                )
            waitABit(1)
        }
        if let frame = onScreenFrame(of: header, in: app) {
            return frame.midY >= bandTop && frame.midY <= bandBottom
        }
        return false
    }

    /// `element`'s frame when it is actually laid out inside the app's bounds, else nil.
    /// Off-list rows report either no element at all or an empty frame.
    private func onScreenFrame(of element: XCUIElement, in app: XCUIApplication) -> CGRect? {
        guard element.exists else { return nil }
        let frame = element.frame
        guard frame.height > 0, frame.maxY > 0, frame.minY < app.frame.height else { return nil }
        return frame
    }

    /// Long-presses one of `header`'s set rows to open the row context menu, and reports
    /// whether it opened. The rows sit a card-layout-dependent distance below the header,
    /// so this probes a few plausible offsets (a press landing in the gap between two rows
    /// opens nothing) and stops at the first one that produces the menu.
    private func openSetContextMenu(
        underHeader header: XCUIElement,
        probe: XCUIElement
    ) -> Bool {
        for dy in [3.0, 4.5, 5.5, 6.5] where !probe.exists {
            header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy))
                .press(forDuration: 0.9)
            _ = probe.waitForExistence(timeout: 3)
        }
        return probe.exists
    }

    // MARK: - Regression tests (reported-bugs session 2026-07-21)

    /// The template editor's rest-duration editor used to flash away after a few seconds
    /// and never reopen: the persistent exercise tray had `presentationBackgroundInteraction
    /// (.enabled)`, and a background-interactive sheet can't stably host a stacked sheet —
    /// UIKit dismissed the tray, SwiftUI re-presented it, and the rest sheet died in the
    /// fight, leaving its `.sheet(item:)` binding stuck. The tray now disables pass-through
    /// while a nested sheet is up. This asserts the sheet survives ~5s and reopens.
    func testTemplateRestEditorStaysPresentedAndReopens() {
        let app = launchApp(scenario: "many")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
        waitABit(1)
        tapTab(app, at: 2) // Templates

        let templateRow = app.staticTexts["Push Day"].firstMatch
        XCTAssertTrue(templateRow.waitForExistence(timeout: 5), "No template row")
        templateRow.tap()
        waitABit(1)

        // Nav-bar ellipsis menu → Edit.
        app.navigationBars.firstMatch.buttons.allElementsBoundByIndex.last?.tap()
        waitABit(1)
        let editButton = app.buttons["Edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 3), "No Edit menu item")
        editButton.tap()
        waitABit(2)

        // Tap the "2:00" rest capsule between set 1 and set 2 (coordinate-based;
        // background elements aren't in the a11y tree while the tray is up).
        // The sheet-presence sentinel is its "Rest Between Sets" caption — unique to the
        // sheet, unlike the preset labels, which collide with the editor's rest capsules.
        let restCapsule = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.287))
        let sheetCaption = app.staticTexts["Rest Between Sets"].firstMatch
        restCapsule.tap()
        waitABit(1)
        XCTAssertTrue(sheetCaption.waitForExistence(timeout: 3), "Rest editor did not present")
        waitABit(4)
        XCTAssertTrue(sheetCaption.exists, "Rest editor dismissed itself within ~5s")
        attach(app, "template_rest_editor_stable")

        // Picking a preset applies it and auto-dismisses…
        app.buttons["1:00"].firstMatch.tap()
        waitABit(2)
        attach(app, "template_rest_editor_after_preset")
        XCTAssertFalse(sheetCaption.exists, "Rest editor should dismiss after picking a preset")

        // …and it must reopen — the stuck-binding regression.
        restCapsule.tap()
        waitABit(2)
        XCTAssertTrue(sheetCaption.waitForExistence(timeout: 3), "Rest editor did not reopen")
        attach(app, "template_rest_editor_reopened")
    }

    /// Keyboard focus is keyed by set UUID (IntegerField.Index.setID), not flat position.
    /// With position keys, inserting a set into an earlier group while later cells hadn't
    /// re-rendered made two fields claim the same index — tapping one focused the other
    /// and typing landed sets earlier (the reported "typing in the squat section" bug).
    /// -UITEST_MINIMAL disables the recorder's throttled re-render heal, freezing exactly
    /// the stale state the production race produces.
    func testRecorderFocusStaysOnTappedFieldAfterInsertingEarlierSet() {
        let app = launchApp(
            scenario: "stress",
            extraArguments: ["-UITEST_SHOW_RECORDER", "-UITEST_NO_SHEET", "-UITEST_MINIMAL", "-UITEST_NO_SCROLLTO"]
        )

        let nameField = app.textFields.matching(NSPredicate(format: "value == 'Push Day'")).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Recorder never presented")
        waitABit(2)

        let addSetButtons = app.buttons.matching(NSPredicate(format: "label == 'Add Set'"))
        let addSet1 = addSetButtons.element(boundBy: 0)
        XCTAssertTrue(addSet1.waitForExistence(timeout: 5))

        // Long-press a set row in group 1 → context menu → "Add Set After" (the one
        // insertion path that doesn't fire workout.objectWillChange).
        let firstField = app.textFields.allElementsBoundByIndex.first {
            $0.frame.minY > 100 && $0.frame.maxY < addSet1.frame.minY
        }
        guard let groupOneField = firstField else {
            XCTFail("No group 1 field found")
            return
        }
        groupOneField.coordinate(withNormalizedOffset: CGVector(dx: -2.5, dy: 0.5))
            .press(forDuration: 1.2)
        let addAfter = app.buttons["Add Set After"].firstMatch
        XCTAssertTrue(addAfter.waitForExistence(timeout: 3), "Context menu Add Set After not found")
        addAfter.tap()
        waitABit(2)

        // Tap the first field of group 2 and type — the digit must land there.
        let addSet1Frame = addSet1.frame
        let fields = app.textFields.allElementsBoundByIndex
        guard let target = fields.first(where: { $0.frame.minY > addSet1Frame.maxY + 10 && $0.isHittable }) else {
            XCTFail("No target field below group 1 found")
            return
        }
        let targetFrame = target.frame
        let valueBefore = target.value as? String ?? ""

        target.tap()
        waitABit(1)
        app.typeText("9")
        waitABit(1)

        let valueAfter = target.value as? String ?? ""
        if !valueAfter.contains("9") || valueAfter == valueBefore {
            let changed = app.textFields.allElementsBoundByIndex.first {
                ($0.value as? String)?.contains("9") == true && $0.frame != targetFrame
            }
            XCTFail("Focus jump: tapped field at y=\(targetFrame.minY) value='\(valueAfter)'; digit landed at y=\(changed?.frame.minY ?? -1)")
        }
    }
}
