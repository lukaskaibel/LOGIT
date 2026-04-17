# Release playbooks

LOGIT ships to the App Store with [fastlane](https://fastlane.tools). All
metadata and screenshot captions are plain text files in this repo, so an
agent can change copy and rerun one lane to push it to App Store Connect.

## Decision tree

```
User wants to ship a new App Store version (e.g. 4.3)?
  → ship-release.md

User wants a TestFlight beta (no App Store release)?
  → ship-testflight.md

User wants to change store copy (description / keywords / what's new / etc.)?
  → update-metadata.md

User wants the screenshots to reflect a UI change, or to restyle captions?
  → refresh-screenshots.md

User only wants the version number bumped?
  → bump-version.md

Something in the pipeline is broken?
  → troubleshooting.md
```

## Key facts the agent must remember

- **Authentication.** Every App Store Connect call uses an API key (`.p8`), so
  no 2FA prompts ever appear. The key is loaded from `fastlane/.env.secret`
  (local) or GitHub Actions secrets (CI). See [`one-time-setup.md`](one-time-setup.md)
  for key paths.
- **Bundle IDs have a leading dot.** They are literally `.com.lukaskbl.LOGIT`
  and `.com.lukaskbl.LOGIT.LOGITWidgetExtension`. Do not "fix" them.
- **Widget version ≡ app version.** Whenever the main app's `MARKETING_VERSION`
  changes, the widget's must change to the exact same value or Apple rejects
  the upload. [`bump-version.md`](bump-version.md) handles both targets in
  lockstep.
- **`LOGITScreenshots` is a dedicated Xcode scheme.** `LOGIT.xcscheme` still
  includes `LOGITTests` (unit tests) in its test action; snapshot uses
  `LOGITScreenshots.xcscheme` so a broken unit test can't block marketing
  screenshots.
- **Framed PNGs are the upload artifact.** The raw `.png` captures from the
  simulator are gitignored; only `*_framed.png` files are committed, so CI
  can upload without running the simulator farm. `.gitignore` enforces this.
- **Never submit for review without the user asking.** Default to uploading
  metadata + build and letting the user hit "Submit for Review" in App Store
  Connect manually, unless they explicitly say "submit for review".

## Lane cheat sheet

| Lane | What it does |
| --- | --- |
| `fastlane screenshots` | Captures raw screenshots in the simulator, then frames them. Local only. |
| `fastlane reframe` | Re-runs frameit on already-captured raws (cheap — no simulator). |
| `fastlane upload_screenshots` | Uploads framed PNGs to App Store Connect only. |
| `fastlane refresh_screenshots` | `screenshots` + `upload_screenshots` in one shot. |
| `fastlane metadata` | Uploads text metadata (description, keywords, release notes, etc.). |
| `fastlane download_metadata` | Pulls the live metadata back into `fastlane/metadata/`. |
| `fastlane download_screenshots` | Pulls the live framed screenshots back into `fastlane/screenshots/`. |
| `fastlane beta` | Archives the app, uploads to TestFlight, notifies internal testers. |
| `fastlane prepare_release` | Uploads metadata + screenshots for the current `MARKETING_VERSION` without submitting for review. Safe to re-run. |
| `fastlane release` | Full end-to-end: build + upload binary + metadata + screenshots + submit for review. Use only when the user explicitly asks to submit. |

All commands run from the repo root. Each command is the same in
`bundle exec fastlane …` form.
