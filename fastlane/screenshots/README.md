# Screenshots

Raw screenshots are produced by `fastlane snapshot` (triggered by the
`screenshots` lane) running the `LOGITUITests` target. They land here:

```
en-US/iPhone 17 Pro Max-01_Home.png
en-US/iPhone 17 Pro Max-02_History.png
de-DE/iPhone 17 Pro Max-01_Home.png
...
```

`fastlane frameit` then consumes every `.png` in these folders along with
`Framefile.json` + the per-locale `*.strings` files and produces a sibling
`*_framed.png` for each. The framed PNGs are what get uploaded to App Store
Connect by the `upload_screenshots` lane.

## Files in this folder

- `Framefile.json` - universal styling (fonts, colors, padding, background).
  Per-screen overrides live in the `data` array. Edit this to restyle the
  framed output.
- `<locale>/keyword.strings` - short accent text (1-2 words) rendered in
  the configured keyword color above each title.
- `<locale>/title.strings` - the headline above each framed device.
- `background.png` - full-bleed background canvas that sits behind the device
  frame. **Must be supplied once** (see below).
- `SF-Pro-Display-Bold.otf`, `SF-Pro-Display-Heavy.otf` - the display fonts
  referenced by `Framefile.json`. **Must be supplied once** (see below).

## One-time assets you still need to add

Apple's SF Pro fonts and a brand-matched background image are not committed
to source control for licensing + binary-size reasons. To finish the setup:

1. Download **SF Pro** from <https://developer.apple.com/fonts/>. Install
   the package, then copy `SF-Pro-Display-Bold.otf` and
   `SF-Pro-Display-Heavy.otf` into this folder.
2. Export a **background.png** sized 1290 x 2796 (6.9" iPhone resolution).
   A solid dark color like `#0A0A0A` or a subtle radial gradient matching
   LOGIT's accent color works well. Place it next to `Framefile.json`.

Once these two pieces are in place, `bundle exec fastlane screenshots`
produces final, upload-ready images on every run.

## Restyling the text

- Change captions: edit `<locale>/title.strings` / `keyword.strings`.
- Change colors/fonts: edit `Framefile.json` (per-screen overrides live in
  the `data` array under the `filter` key).

You do not need to re-run the simulator to restyle - just rerun
`bundle exec fastlane frame_screenshots` and frameit will rebuild the
framed images from the existing raw captures.
