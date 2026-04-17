# Bump the app version

Use this when the user says "bump to 4.3", "update the version", or a larger
playbook like [`ship-release.md`](ship-release.md) references it.

## What "version" means here

There are two distinct numbers, and you must update **both targets** (app
and widget) in lockstep or App Store Connect rejects the upload.

| Concept | Key in pbxproj | Key in Info.plist | Example |
| --- | --- | --- | --- |
| Marketing version (user-visible) | `MARKETING_VERSION` | `CFBundleShortVersionString` | `4.2` |
| Build number (internal) | `CURRENT_PROJECT_VERSION` | `CFBundleVersion` | `3` |

LOGIT has two targets that both need the same marketing version:

- `LOGIT` (main app) — configured in `LOGIT/App/Info.plist` + `project.pbxproj`
- `LOGITWidgetExtension` — configured in `LOGITWidgetExtension/Info.plist` + `project.pbxproj`

## Bump the marketing version (e.g. `4.2` → `4.3`)

### Step 1: Info.plists via agvtool

Fastlane wraps `agvtool`, which walks every Info.plist in the project:

```zsh
bundle exec fastlane run increment_version_number \
  version_number:<X.Y> xcodeproj:LOGIT.xcodeproj
```

Verify:

```zsh
grep -A1 "CFBundleShortVersionString" \
  LOGIT/App/Info.plist LOGITWidgetExtension/Info.plist
```

Both should print `<X.Y>`.

### Step 2: pbxproj MARKETING_VERSION

agvtool doesn't touch the `MARKETING_VERSION` build setting, and that
setting trumps the Info.plist value when building from the command line.
Update it directly:

```zsh
# Replace every MARKETING_VERSION line except the legacy 1.0 stubs.
sed -i '' "s/MARKETING_VERSION = [0-9][0-9.]*;/MARKETING_VERSION = <X.Y>;/g" \
  LOGIT.xcodeproj/project.pbxproj

# Restore the legacy 1.0 entries (they are for long-obsolete targets and
# should stay at 1.0). The current pbxproj has two such entries.
# Check the diff and revert anything surprising:
git diff LOGIT.xcodeproj/project.pbxproj
```

If the diff shows MARKETING_VERSION changing on targets other than
`LOGIT` and `LOGITWidgetExtension`, manually revert those hunks.

Confirm:

```zsh
xcodebuild -project LOGIT.xcodeproj -scheme LOGIT \
  -configuration Release -destination 'generic/platform=iOS' \
  -showBuildSettings 2>/dev/null | grep "^\s*MARKETING_VERSION"
```

Expect `MARKETING_VERSION = <X.Y>`.

## Bump the build number

Usually you do **not** set this manually — `fastlane beta` / `fastlane release`
set it to `latest_testflight_build_number + 1` automatically at upload time.

Only set it by hand if the user specifically asks, or if you need a clean
starting point after a marketing version bump:

```zsh
bundle exec fastlane run increment_build_number \
  build_number:<N> xcodeproj:LOGIT.xcodeproj

# And mirror into pbxproj:
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = <N>;/g" \
  LOGIT.xcodeproj/project.pbxproj
```

`agvtool` writes to every Info.plist, so both targets get `<N>`.

## Sanity checklist after bumping

```zsh
grep -A1 "CFBundleShortVersionString\|CFBundleVersion" \
  LOGIT/App/Info.plist LOGITWidgetExtension/Info.plist
grep "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" \
  LOGIT.xcodeproj/project.pbxproj
```

All non-legacy entries should show the new version / build.

## Commit

Include every touched file in one commit so bisecting stays sane:

```zsh
git add LOGIT.xcodeproj/project.pbxproj \
        LOGIT/App/Info.plist \
        LOGITWidgetExtension/Info.plist
git commit -m "Bump version to <X.Y>"
```

Don't push yet if you're in the middle of [`ship-release.md`](ship-release.md)
— that playbook commits version bump + release notes together.
