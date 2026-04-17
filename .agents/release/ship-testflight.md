# Ship a TestFlight beta

Use this when the user says "push a new beta / TestFlight build / internal
build" but is **not** creating a new App Store version. If they want an
App Store release, read [`ship-release.md`](ship-release.md) instead.

## What `fastlane beta` does

1. `sync_code_signing(type: "appstore", readonly: is_ci)` — downloads the
   App Store distribution cert + provisioning profiles from the match repo.
2. `latest_testflight_build_number` — queries App Store Connect for the
   highest existing build number on the current marketing version.
3. `increment_build_number` — sets the new build number to that + 1, both
   in `project.pbxproj` and the two `Info.plist` files. The committed
   MARKETING_VERSION is not touched.
4. `build_app` — clean + archive + export an `app-store` IPA with manual
   signing, symbols on, bitcode off. Output lands in `fastlane/builds/`.
5. `upload_to_testflight` — uploads the IPA, waits for processing, sets
   the "What to test" changelog from `fastlane/metadata/en-US/release_notes.txt`,
   and distributes to internal testers only.

## Decide: does the marketing version need bumping first?

- **Same `MARKETING_VERSION` as the current live App Store release.**
  `fastlane beta` will succeed and produce `<current version> (<N+1>)`.
- **A new App Store version is planned** (e.g. live is `4.1.1`, you want
  to push beta `4.2 (1)`). Bump MARKETING_VERSION first using
  [`bump-version.md`](bump-version.md), then run beta. TestFlight will
  start build numbering fresh under the new version.

## Run it

```zsh
bundle exec fastlane beta
```

Expect 3–6 minutes for archive + export and 3–5 minutes for the TestFlight
upload + processing wait.

## If it hangs

See [`troubleshooting.md`](troubleshooting.md), specifically the "codesign
hang" section — that's the most common failure, caused by keychain access
prompts.

## After it finishes

The success message prints the version/build it distributed:

```
Successfully distributed build to Internal testers 🚀
```

Tell the user the build (`<X.Y> (<N>)`) is on TestFlight for internal
testers and link to App Store Connect → TestFlight if useful.

## Side effects to commit

`fastlane beta` bumps the build number inside:

- `LOGIT.xcodeproj/project.pbxproj` (`CURRENT_PROJECT_VERSION`)
- `LOGIT/App/Info.plist` (`CFBundleVersion`)
- `LOGITWidgetExtension/Info.plist` (`CFBundleVersion`)

Commit those with a short message like `TestFlight build <N>` unless the
user says not to commit the build bump.
