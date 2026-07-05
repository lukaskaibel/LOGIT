# UI verification: scenario matrix (mandatory for UI changes)

Every user-visible UI change must be verified in the simulator across the
app's critical data states, and the screenshots must be shown to the user in
the final response (clickable file paths per scenario; for larger matrices
also render an HTML contact sheet so the states can be compared side by side).
Point out any scenario where the change looks wrong or degenerate.

The states, all driven by launch arguments (DEBUG builds only, implemented in
`LOGIT/App/TestScenarios.swift`):

| State | Launch arguments |
| --- | --- |
| Empty (brand-new user, 0 workouts, no goal) | `-SCENARIO empty` |
| One workout (single data points, fresh trends) | `-SCENARIO one` |
| Many workouts (long-time user, rich history) | `-SCENARIO many` |
| Free tier (Pro locked) | add `-UITEST_FORCE_FREE` to any scenario |
| Stress (2 years dense history + in-progress workout; for performance work, not part of the standard matrix) | `-SCENARIO stress`, add `-UITEST_SHOW_RECORDER 1` to land in the recorder |

Standard matrix for a change: **empty, one, many (Pro implied on the
simulator) + the free variant of the most relevant scenario.** If the change
touches a Pro-gated feature, always show Pro vs. free side by side.

How scenarios work (so you don't fight them):

- A scenario boots a **fresh in-memory store** seeded for that state plus
  session-only UserDefaults overrides in the argument domain. Nothing
  persists, every launch is identical, and the simulator's real store and
  defaults are untouched. Flip side: overridden keys (`setupDone`,
  `weightUnit`, `workoutPerWeekTarget`, `pinnedExercises`,
  `pinnedMeasurements`, `muscleTargetSplit`, default-content version keys)
  read as pinned for the whole session, so tests/interactions that must
  *change* one of those keys should launch without the scenario instead.
- `many` is the curated preview dataset **without** the in-progress workout.
  Use `-UITEST_FIXTURES 1` when the mid-workout state (recorder, mini bar)
  is itself under test.
- Pro is force-unlocked in DEBUG simulator builds; `-UITEST_FORCE_FREE` is
  the only way to see locked/teaser states.

Capturing the matrix (agents; user is usually away — never wait for manual
checks):

1. Run the standing suite `LOGITUITests/ScenarioScreenshots.swift` — it walks
   the four tab roots per scenario and attaches screenshots:

   ```
   xcodebuild test -workspace LOGIT.xcworkspace -scheme LOGITScreenshots \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
     -only-testing:LOGITUITests/ScenarioScreenshots \
     -resultBundlePath /tmp/scenarios.xcresult
   xcrun xcresulttool export attachments --path /tmp/scenarios.xcresult \
     --output-path /tmp/scenario-shots
   ```

   Use the **iOS 26.4** simulator runtime — the 26.0 runner dies
   nondeterministically. To capture only the states relevant to a small
   change, narrow further, e.g.
   `-only-testing:LOGITUITests/ScenarioScreenshots/testEmptyScenario`.
2. If the changed screen is not a tab root, temporarily add a test method to
   `ScenarioScreenshots.swift` that uses `launchApp(scenario:)` and navigates
   to it in each relevant scenario (one launch per test method — relaunching
   within a method kills the iOS 26 test runner). Remove the temp method
   afterwards.
3. Read the exported PNGs to verify the change yourself before showing them.

For manual testing there are shared schemes with the arguments preconfigured:
**LOGIT Empty / LOGIT One Workout / LOGIT Many Workouts** (each also carries a
disabled `-UITEST_FORCE_FREE` toggle — tick it in Edit Scheme for the free
tier). The plain LOGIT scheme keeps using the real on-disk store.

# App Store automation (Fastlane)

LOGIT ships to the App Store via [fastlane](https://fastlane.tools). All store
copy and screenshot captions live as plain text files under `fastlane/`, so an
agent can edit text and rerun a single lane to push changes live.

## Quick reference

| Task | Command |
| --- | --- |
| Update description / release notes / keywords | edit `fastlane/metadata/<locale>/*.txt`, then `bundle exec fastlane metadata` |
| Pull current live metadata into repo | `bundle exec fastlane download_metadata` |
| Pull current live screenshots into repo | `bundle exec fastlane download_screenshots` |
| Regenerate screenshots after UI change | `bundle exec fastlane screenshots` |
| Restyle screenshot captions / colors only | edit `fastlane/screenshots/**`, then `bundle exec fastlane reframe` |
| Capture + frame + upload in one shot | `bundle exec fastlane refresh_screenshots` |
| Ship a new TestFlight build | `bundle exec fastlane beta` |
| Submit a new App Store release | tag `vX.Y.Z` and push, or `bundle exec fastlane release` |

All lanes authenticate with an App Store Connect API key (`.p8`), so no 2FA
prompts ever appear.

## What lives where

- `Gemfile` - pins fastlane + xcpretty. Run `bundle install` once.
- `fastlane/Appfile` - app identifier, Apple ID, team IDs.
- `fastlane/Matchfile` - points at the private cert repo.
- `fastlane/Fastfile` - all lanes (see table above).
- `fastlane/Snapfile` - snapshot devices (6.9" iPhone) + locales
  (`en-US`, `de-DE`, `es-MX`, `es-ES`, `fr-FR`, `pt-BR`, `ja`, `ko`, `it`).
- `fastlane/metadata/<locale>/*.txt` - App Store Connect store listing copy.
  One field per file; edit and upload via `fastlane metadata`.
- `fastlane/screenshots/<locale>/title.strings` - headlines drawn above each
  framed screenshot.
- `fastlane/screenshots/<locale>/keyword.strings` - short (1-2 word) accent
  text drawn in a highlight color above the title.
- `fastlane/screenshots/Framefile.json` - universal styling (fonts, colors,
  padding, background) with per-screenshot overrides.
- `LOGITUITests/LOGITScreenshots.swift` - one test method per screen. Add a
  new method + update `title.strings` / `keyword.strings` to add a new
  marketing screenshot.
- `LOGIT/App/ScreenshotFixtures.swift` - routes the app to the seeded
  in-memory preview database when launched with `-UITEST_FIXTURES 1`.

## One-time setup (humans only)

This only needs to happen once per machine.

1. **Install toolchain**
   ```
   bundle install
   ```
2. **Bootstrap the UI test target.** The UI test target isn't in the Xcode
   project yet; run this helper to add it using the `xcodeproj` gem that
   ships with fastlane:
   ```
   bundle exec ruby fastlane/bootstrap_uitest_target.rb
   ```
   Then open Xcode once so the shared scheme gets regenerated.
3. **Generate an App Store Connect API key.** App Store Connect -> Users
   and Access -> Integrations -> App Store Connect API -> generate a key
   with role "App Manager". Download the `.p8`, note the Key ID + Issuer
   ID. Fastlane needs the same key in two shapes - the raw `.p8` (for
   Fastfile lanes) and a JSON config wrapper (for direct CLI tools like
   `fastlane match` and `fastlane deliver`):
   ```
   mkdir -p ~/.appstoreconnect
   mv /path/to/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/
   chmod 600 ~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
   jq -Rn --arg k "$(cat ~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8)" \
     '{key_id:"XXXXXXXXXX", issuer_id:"00000000-0000-...", key:$k, in_house:false}' \
     > ~/.appstoreconnect/asc_api_key.json
   chmod 600 ~/.appstoreconnect/asc_api_key.json
   cp fastlane/.env.secret.example fastlane/.env.secret
   # edit with the real paths + IDs
   ```
4. **Set up `fastlane match`** with a new private repo (e.g.
   `lukaskaibel/logit-certs`):
   ```
   bundle exec fastlane match appstore
   ```
5. **Drop in the frameit assets** that aren't checked in for licensing
   reasons. See `fastlane/screenshots/README.md` for the two files you
   need to add manually (SF Pro fonts + `background.png`).
6. **Pull the authoritative metadata from App Store Connect** to replace
   the placeholder copy that was scaffolded in the repo:
   ```
   bundle exec fastlane download_metadata
   ```

## GitHub Actions

`.github/workflows/release.yml` runs the same lanes in CI:

- Push tag `vX.Y.Z` -> runs `fastlane release` automatically.
- `workflow_dispatch` -> pick any lane (`beta`, `release`, `metadata`,
  `upload_screenshots`) from the UI.

Required GitHub Actions secrets:

- `APP_STORE_CONNECT_API_KEY_KEY_ID`
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_CONTENT` (base64 of the `.p8` contents)
- `MATCH_GIT_URL` (e.g. `https://github.com/lukaskaibel/logit-certs.git`)
- `MATCH_GIT_BASIC_AUTHORIZATION` (base64 of `user:personal_access_token`)
- `MATCH_PASSWORD`
- `SECRETS_SWIFT_CONTENT` (the literal contents of `LOGIT/Config/Secrets.swift`)

Screenshot capture stays local by default because running `xcodebuild test`
against multiple simulators on CI is slow and fragile - but
`upload_screenshots` does work in CI since it only needs the framed PNGs
that are committed to the repo.

## Conventions for agents

- Screenshot names follow `NN_Name` (e.g. `01_Home`, `02_History`) and the
  same key must exist in both `title.strings` and `keyword.strings` for
  both locales.
- Release notes must stay under 4000 characters per locale and should not
  contain Markdown - App Store Connect renders them as plain text.
- **Localization is mandatory for user-facing text.** LOGIT currently supports
  app locales `en`, `de`, `es`, `fr`, `pt-BR`, `ja`, `ko`, and `it`, plus App
  Store locales `en-US`, `de-DE`, `es-MX`, `es-ES`, `fr-FR`, `pt-BR`, `ja`,
  `ko`, and `it`. Any change that adds or edits user-facing text must update
  all supported `Localizable.strings` files. If the change affects App Store
  copy or screenshots, update every matching `fastlane/metadata/<locale>` and
  `fastlane/screenshots/<locale>` file. If the change touches default
  exercises, localize both the `_default.exercise.*` names and the localized
  instruction arrays in `LOGIT/Resources/default_exercises.json`. Default
  templates (`LOGIT/Resources/default_templates.json`) keep their structure in
  the JSON but localize their `_default.template.*` names and descriptions in
  every `Localizable.strings` file.
- Keep translations close to the English length where possible, but do not make
  them awkward. Use natural Apple-style platform wording, preserve product
  terms such as iCloud, App Store, Live Activity, Dynamic Island, and LOGIT Pro,
  and use normal fitness terminology for each locale.
- Localized legal Markdown files include machine-translated text for app
  coverage. Treat legal text as requiring human/legal review before release.
- Never commit `fastlane/.env.secret`, the raw `.p8`, or anything inside
  `fastlane/builds/` - these are all gitignored.
- If a UI change breaks one of the screenshot UI tests, update the
  navigation inside `LOGITUITests/LOGITScreenshots.swift` rather than
  skipping the test.

## Known quirks

- **Leading-dot bundle ID.** The registered App IDs in Apple's Developer
  Portal are literally `.com.lukaskbl.LOGIT` and
  `.com.lukaskbl.LOGIT.LOGITWidgetExtension` (with a leading dot), which
  matches the value already in `project.pbxproj`. `fastlane/Appfile`,
  `fastlane/Matchfile`, and the `XCUIApplication(bundleIdentifier:)` call
  in `LOGITScreenshots.swift` therefore also use `.com.lukaskbl.LOGIT`.
  Do not "fix" this without also re-registering the App IDs on
  developer.apple.com and updating the Xcode project in lock-step - it
  would invalidate the existing provisioning profiles and break uploads.
- **Widget version must match app version.** The widget's
  `CFBundleShortVersionString` must equal the main app's (e.g. both
  `4.1.1`). If you bump the app version, bump the widget too or Apple
  rejects the build at submission.
- **`LOGITScreenshots` is a separate scheme.** `LOGIT.xcscheme` still
  includes `LOGITTests` (the unit test bundle) in its test action, but
  fastlane snapshot uses a dedicated `LOGITScreenshots.xcscheme` so a
  broken unit test can't block marketing screenshots.
