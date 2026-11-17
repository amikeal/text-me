# Cubby

**Notes to self, sorted for you.** Drop it in. Find it later.

Cubby is an iPhone app for capturing anything (a to-do, a link, a thought) as fast as texting
yourself. You never file or tag anything. Cubby sorts entries into To-dos, Links and Notes on
the device, reminds you when something with a date comes due, and sums up your week.

- One input. The app opens to a blank page with the keyboard up (or, if you prefer, to the
  timeline with the keyboard up; it's a setting).
- Everything lands in one timeline, verbatim. Filters are views over it, never folders.
- Sorting runs on the device: Apple Intelligence (Foundation Models) where available,
  built-in rules everywhere else. Long-press any entry to correct it.
- No server. Entries sync through the user's own iCloud.
- Light and dark mode, Liquid Glass controls.

## Status

Version 0.1, unreleased. The app, share extension, widget, Control Center control and Siri
shortcut are written; core logic has unit tests. See [What's verified](#whats-verified).

## Build and run

Requirements: a Mac with **Xcode 26** and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate        # creates Cubby.xcodeproj from project.yml
open Cubby.xcodeproj
```

Pick an iPhone simulator and press Run. The simulator needs no signing setup.

**Try it with sample content:** Product › Scheme › Edit Scheme › Run › Arguments, add
`-cubbyDemo`. Demo mode uses an in-memory store, so nothing you type is kept. Also handy:
`-startScreen timeline` and `-appearance dark`.

**On a real iPhone, with iCloud sync:** create `Config/Local.xcconfig` (ignored by git):

```
DEVELOPMENT_TEAM = ABCDE12345
CUBBY_BUNDLE_ID = com.yourname.cubby
```

Then run `xcodegen generate` again. The App Group (`group.<bundle id>`) and iCloud container
(`iCloud.<bundle id>`) are derived from the bundle ID; Xcode's automatic signing registers them.
Apple Intelligence sorting needs an Apple Intelligence–capable iPhone with it turned on;
other devices use the built-in rules.

## Tests

```sh
cd Packages/CubbyCore && swift test
```

CI (`.github/workflows/ci.yml`) runs these tests, builds the app for the simulator, and uploads
light and dark screenshots of both opening screens with demo data.

## Classifier evaluation

Measure sorting accuracy on real notes before trusting it: see [`eval/README.md`](eval/README.md)
and the plan in [`docs/classifier-eval-plan.md`](docs/classifier-eval-plan.md).

## Project layout

| Path | What's there |
|---|---|
| `Packages/CubbyCore` | Platform-independent logic: date parsing, link detection, rule-based and Foundation Models classification, share inbox, widget data, digest wording. Unit-tested. |
| `Cubby/` | The app: SwiftData model, capture and timeline screens, search, settings, notifications, Siri shortcut. |
| `CubbyShare/` | Share extension. Writes to a shared inbox; the app imports and sorts on next open. |
| `CubbyWidget/` | Home Screen / Lock Screen widget and Control Center control. |
| `SharedIntents/` | The "New Cubby Note" intent, compiled into the app and the widget. |
| `Config/` | Build settings: team, bundle ID, App Group, iCloud container. |
| `eval/` | Classifier evaluation harness (Swift) and scorer (Python). |
| `Tools/make_assets.py` | Regenerates the color sets and placeholder app icon. |
| `docs/` | Product spec, eval plan, naming research. |

## What's verified

- **Core logic** (`CubbyCore`): unit tests for date parsing, classification, link detection, the
  share inbox, widget data, deadline labels and the digest.
- **Scorer** (`eval/score.py`): tested against predictions with known errors.
- **App, extensions and widget**: compiled and screenshotted by CI on GitHub's macOS runners.
  The code was written without local access to Xcode, so check CI before relying on a build.
- **Not yet verified on a device**: iCloud sync, notifications, the share extension, the widget,
  Siri, and Foundation Models sorting quality (run the eval).

## Docs

- [Product spec](docs/product-spec.md)
- [Classifier eval plan](docs/classifier-eval-plan.md)
- [Naming research](docs/naming.md)
