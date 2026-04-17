# Update App Store metadata

Use this when the user wants to change store copy — description, keywords,
promotional text, subtitle, "What's New", etc. — without shipping a new
binary.

## File layout

Everything lives under `fastlane/metadata/`. One field per file.

### Localized (`fastlane/metadata/<locale>/`)

Supported locales: `en-US`, `de-DE`.

| File | Purpose | App Store Connect limit |
| --- | --- | --- |
| `name.txt` | App name | 30 chars |
| `subtitle.txt` | Short tagline under the name | **30 chars** — see gotcha below |
| `description.txt` | Long description | 4000 chars |
| `keywords.txt` | Comma-separated keywords | 100 chars total |
| `promotional_text.txt` | Promo banner (editable without resubmitting) | 170 chars |
| `release_notes.txt` | "What's New" for the current version | 4000 chars |
| `support_url.txt` | Support URL | valid URL |
| `marketing_url.txt` | Marketing URL | valid URL |
| `privacy_url.txt` | Privacy policy URL | valid URL |

### Shared (`fastlane/metadata/`)

| File | Purpose |
| --- | --- |
| `copyright.txt` | Copyright line |
| `primary_category.txt` | Primary App Store category |
| `secondary_category.txt` | Secondary category |
| `primary_first_sub_category.txt`, `primary_second_sub_category.txt` | Sub-categories |
| `review_information/*.txt` | Reviewer contact + (if needed) demo credentials |

## Character-count gotchas

- **Subtitle is UTF-8 character-counted, not byte-counted.** German text
  with umlauts (`ä`, `ö`, `ü`, `ß`) counts each character as 1 even though
  it's 2 UTF-8 bytes. Use Python to count safely:
  ```zsh
  python3 -c "print(len(open('fastlane/metadata/de-DE/subtitle.txt').read().strip()))"
  ```
  If the number is > 30, trim. `wc -c` will lie (it prints bytes).
- **Release notes.** Plain text only. Apple renders Markdown literally.
  Keep line breaks as real newlines.
- **Keywords.** Separate with commas, no spaces. The combined string
  (including commas) must be ≤ 100 characters.

## Edit

Open the relevant `.txt` file, change the copy, save. One field per file;
never combine fields.

If adding a brand-new locale, create a new subdirectory and populate at
least `description.txt`, `keywords.txt`, `release_notes.txt`, and the
URL files. Then also localize:

- `fastlane/screenshots/<locale>/title.strings`
- `fastlane/screenshots/<locale>/keyword.strings`

and add the locale to `fastlane/Snapfile`.

## Upload

```zsh
# Metadata only — leaves the binary and screenshots alone.
bundle exec fastlane metadata
```

This uploads to whatever App Store version is currently in "Prepare for
Submission". If the user wants to update the *live* version's editable
fields (promotional text only, basically), use:

```zsh
bundle exec fastlane run upload_to_app_store \
  metadata_path:./fastlane/metadata \
  edit_live:true \
  skip_binary_upload:true \
  skip_screenshots:true \
  force:true \
  precheck_include_in_app_purchases:false \
  run_precheck_before_submit:false
```

## Commit

```zsh
git add fastlane/metadata
git commit -m "Update <locale> <field> copy"
git push origin main
```

## Syncing from App Store Connect

If the user edited copy directly in the App Store Connect web UI and wants
to pull it back into the repo:

```zsh
bundle exec fastlane download_metadata
```

This rewrites `fastlane/metadata/**` with whatever is live. Diff and commit.
