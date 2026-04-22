# App Store metadata

Each file in this folder maps directly to a field in App Store Connect.
Agents and humans edit plain text here and then run:

```
bundle exec fastlane metadata
```

to push changes live.

## Folder layout

- `en-US/`, `de-DE/`, `es-MX/`, `es-ES/`, `fr-FR/`, `pt-BR/`, `ja/`, `ko/`,
  `it/` - per-locale store listing copy
  - `name.txt` - app name (30 char limit)
  - `subtitle.txt` - subtitle (30 char limit)
  - `description.txt` - full description (4000 char limit)
  - `keywords.txt` - comma-separated keywords (100 char limit)
  - `promotional_text.txt` - changeable without new build (170 char limit)
  - `release_notes.txt` - "What's New" text for the next version
  - `marketing_url.txt`, `support_url.txt`, `privacy_url.txt`
- `copyright.txt`, `primary_category.txt` - locale-independent values
- `review_information/` - contact info shown to the Apple reviewer

## First-time bootstrap

These files were seeded with sensible defaults. To replace them with the exact
copy currently live on App Store Connect, run once:

```
bundle exec fastlane deliver download_metadata
```

This overwrites the `.txt` files with the authoritative version from ASC.
