# Ship a new App Store version

Use this when the user says things like "ship 4.3", "release the next
version", "cut a new App Store release". This playbook produces a fully
populated "Prepare for Submission" version in App Store Connect that the
user can verify and then submit manually.

> **Do not submit for review unless the user explicitly says so.** Stop
> after step 6 and hand off to the user. If they also asked you to submit,
> follow the final "Submit for review" section.

## 0. Context to gather

Before touching anything, make sure you know:

1. **Target version** (e.g. `4.3`). Ask if unclear.
2. **Main headline feature** for the release notes. Ask if unclear — this is
   what goes into "What's New" in en-US + de-DE.
3. **Does the UI look different from the committed screenshots?** If yes,
   screenshots need regenerating ([`refresh-screenshots.md`](refresh-screenshots.md))
   before step 5. If no, reuse the committed framed PNGs.

## 1. Make sure the working tree is clean

```zsh
git status
```

If there are unrelated uncommitted changes, either commit them first or ask
the user how they want to handle them. Fastlane will modify `project.pbxproj`
and `Info.plist` files in step 2, so starting from a clean tree makes the
commit afterwards easy to reason about.

## 2. Bump the version

Follow [`bump-version.md`](bump-version.md). The short version:

```zsh
bundle exec fastlane run increment_version_number \
  version_number:<X.Y> xcodeproj:LOGIT.xcodeproj

# Also update MARKETING_VERSION inside project.pbxproj (agvtool doesn't).
sed -i '' "s/MARKETING_VERSION = [0-9][0-9.]*;/MARKETING_VERSION = <X.Y>;/g" \
  LOGIT.xcodeproj/project.pbxproj
```

Verify both `LOGIT/App/Info.plist` and `LOGITWidgetExtension/Info.plist`
show the new `CFBundleShortVersionString`. If they don't match, stop.

## 3. Write the release notes

Edit both files (plain text, no Markdown, ≤4000 chars, keep tone consistent
with past releases — peek at git history for prior `release_notes.txt` to
match voice):

- `fastlane/metadata/en-US/release_notes.txt`
- `fastlane/metadata/de-DE/release_notes.txt`

Structure that has worked before:

```
<One-line hook naming the headline feature>.

· <Primary feature, 1–2 sentences>
· <Supporting improvement>
· <Bug fixes / performance>

Thanks for training with LOGIT!
```

## 4. (Optional) Update other store copy

If the user asked for other copy changes, edit the relevant files under
`fastlane/metadata/<locale>/*.txt`. Respect App Store Connect character
limits — see [`update-metadata.md`](update-metadata.md) for the list.

## 5. (Optional) Refresh screenshots

Only if the UI has changed or the user asked. Follow
[`refresh-screenshots.md`](refresh-screenshots.md). Come back here when
the framed PNGs under `fastlane/screenshots/<locale>/` are up to date.

## 6. Build, upload binary, upload store listing

Run in order. Each command can take several minutes — be patient, don't kill
them unless truly stuck (see [`troubleshooting.md`](troubleshooting.md)).

```zsh
# 6a. Archive + upload a new build to TestFlight. This auto-increments
#     the build number based on the latest TestFlight build.
bundle exec fastlane beta

# 6b. Upload metadata + framed screenshots to the new App Store version.
#     Reads MARKETING_VERSION from the Xcode project, creates the
#     "Prepare for Submission" version in App Store Connect, and
#     uploads everything without submitting for review.
bundle exec fastlane prepare_release
```

After `prepare_release` finishes, the user can go to **App Store Connect →
LOGIT → iOS App `<X.Y>`** and verify the release notes, screenshots, and
build binding look right.

## 7. Commit and push

```zsh
git add -A
git commit -m "Bump to <X.Y> (<headline feature>)

<optional bullets>"
git push origin main
```

Ensure the commit includes:

- `LOGIT.xcodeproj/project.pbxproj` (MARKETING_VERSION + CURRENT_PROJECT_VERSION bumps)
- `LOGIT/App/Info.plist`, `LOGITWidgetExtension/Info.plist` (version updates)
- `fastlane/metadata/*/release_notes.txt`
- Any other edited metadata or screenshot files

## 8. Hand off

Tell the user:

- TestFlight build `<X.Y> (<build number>)` is uploaded and processed.
- The App Store version `<X.Y>` is populated with metadata + screenshots
  and waiting in "Prepare for Submission".
- They should verify in App Store Connect and click **Submit for Review**
  when happy.

## Submit for review (only if explicitly requested)

```zsh
bundle exec fastlane release submit_for_review:true automatic_release:false
```

- `automatic_release:false` → the user still chooses when to go live after
  Apple approves.
- `automatic_release:true` → Apple releases the approved build immediately.
  Only set this if the user explicitly asks.

The `release` lane rebuilds + re-uploads the binary. If the current
TestFlight build `<X.Y> (<N>)` is already what you want to submit and you
don't want a new build number, prefer this instead:

```zsh
bundle exec fastlane run upload_to_app_store \
  app_version:<X.Y> \
  metadata_path:./fastlane/metadata \
  screenshots_path:./fastlane/screenshots \
  submit_for_review:true \
  automatic_release:false \
  force:true \
  skip_binary_upload:true \
  overwrite_screenshots:true \
  precheck_include_in_app_purchases:false \
  run_precheck_before_submit:false
```
