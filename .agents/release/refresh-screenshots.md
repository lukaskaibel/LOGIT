# Refresh App Store screenshots

Use this when:

- The UI has changed and the committed framed screenshots no longer reflect
  the app.
- The user wants to restyle captions, colors, or layout without re-running
  the simulator.
- A new marketing screen needs to be added to the set.

## What's committed vs. generated

- **Framed PNGs** (`fastlane/screenshots/<locale>/iPhone <model>-NN_*_framed.png`)
  are committed. These are what App Store Connect receives.
- **Raw PNGs** (same path without `_framed`) are gitignored. They are
  regenerated every time the simulator runs.
- **`background.png`, `SF-Pro-Display-*.otf`** — committed once (see
  [`one-time-setup.md`](one-time-setup.md)); not regenerated.

## Pieces involved

- `fastlane/Snapfile` — devices + locales. Currently `iPhone 17 Pro Max`
  (6.9") + `iPhone 16 Plus` (6.5"), `en-US` + `de-DE`.
- `LOGITUITests/LOGITScreenshots.swift` — one `testNN_<Name>()` per
  screen. The `snapshot("NN_Name")` call inside each test names the output
  PNG. **The name must match the keys in `*.strings` below.**
- `LOGIT/App/ScreenshotFixtures.swift` + `LOGIT/Data/Database/Database+Preview.swift`
  — seed the in-memory database when the app is launched with
  `-UITEST_FIXTURES 1`. Change these if the screenshot needs more or
  different fixture data (e.g. more templates, different exercise history).
- `fastlane/screenshots/<locale>/title.strings` — headline above each framed
  device.
- `fastlane/screenshots/<locale>/keyword.strings` — short (1–2 word) accent
  text drawn above the title in a highlight color.
- `fastlane/screenshots/Framefile.json` — universal framing style (fonts,
  colors, padding, `stack_title`, etc.) with per-screenshot overrides in
  the `data` array, keyed by filename stem (`filter: "01_Home"`).
- `fastlane/frameit_devices_patch.rb` — monkeypatch that teaches frameit
  about iPhone 15/16/17 resolutions and fixes an ImageMagick fill-order
  bug. Required; loaded by `Fastfile`.

## Task: restyle only (no simulator run)

Cheap: just edits text + reruns frameit on existing raw PNGs.

```zsh
# Edit captions:
$EDITOR fastlane/screenshots/en-US/title.strings
$EDITOR fastlane/screenshots/de-DE/title.strings
$EDITOR fastlane/screenshots/en-US/keyword.strings
$EDITOR fastlane/screenshots/de-DE/keyword.strings

# And/or edit styling:
$EDITOR fastlane/screenshots/Framefile.json

bundle exec fastlane reframe
```

Inspect the new `*_framed.png` files and iterate. When happy, commit and
(optionally) upload:

```zsh
git add fastlane/screenshots
git commit -m "Restyle App Store screenshot captions"
bundle exec fastlane upload_screenshots   # if pushing to ASC immediately
```

## Task: regenerate from the current UI

Heavier: boots both simulators, runs `LOGITUITests/LOGITScreenshots.swift`
against them for both locales, then frames every capture. Expect 8–15 min.

```zsh
bundle exec fastlane screenshots
```

Under the hood this calls `capture_ios_screenshots` (aka snapshot) on the
`LOGITScreenshots` Xcode scheme. It clears previous raws, records the
status bar via `override_status_bar`, and runs simulators concurrently.

Inspect the framed output (`fastlane/screenshots/<locale>/*_framed.png`).
Things to check:

- The tab bar and top navigation are **not** clipped.
- Fixture data is visible (Templates list is populated, Exercise Detail
  has charts, etc.). If empty, fix the fixture seeding in
  `Database+Preview.swift` before re-running.
- Captions are readable and don't collide with the device frame.

## Task: add a new marketing screenshot

1. Add a `testNN_<Name>()` method in
   `LOGITUITests/LOGITScreenshots.swift`. Use `tapTab(at:)`, element
   queries, and `waitABit()` to navigate reliably. End with
   `snapshot("NN_Name")`.
2. Add a matching `"NN_Name" = "...";` entry to **both**
   `en-US/title.strings` and `de-DE/title.strings`.
3. Add a matching `"NN_Name" = "WORD";` entry to **both**
   `en-US/keyword.strings` and `de-DE/keyword.strings`.
4. Optionally override colors for that screen with a new entry in the
   `data` array of `Framefile.json` keyed by `filter: "NN_Name"`.
5. If the new screen needs seed data that doesn't exist yet, edit
   `LOGIT/Data/Database/Database+Preview.swift`.
6. Run `bundle exec fastlane screenshots` and inspect.

## Upload

```zsh
# Captured + framed + uploaded in one shot:
bundle exec fastlane refresh_screenshots

# Or just upload the committed framed PNGs (cheapest; works on CI):
bundle exec fastlane upload_screenshots
```

## Known UI-test gotchas

- The app must be launched with bundle identifier `.com.lukaskbl.LOGIT`
  (leading dot) or `snapshot` fails to attach. That's already hardcoded in
  `LOGITScreenshots.swift`; do not "fix" it.
- Tabs are indexed 0-based by `tapTab(at:)`. As of 4.2 the order is
  `0=Home, 1=History, 2=Workout, 3=Search, 4=Settings`.
- Always pair `waitForExistence(timeout:)` with a fallback path that taps
  a generic first-matching element — seeding can drift between runs and
  you don't want one rename to break the whole set.
