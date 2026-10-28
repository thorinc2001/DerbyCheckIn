# Architecture

Two Mac apps for pinewood derby check-in that feed GrandPrix Race Manager (GPRM):

- **Derby Check-In**: a native app for one check-in computer.
- **Derby Web Check In**: runs on one Mac and serves the same screens to any browser on the local network.

## Targets

```text
DerbyCheckIn (app) ──┐
                     ├──> DerbyKit ──> DerbyCore
DerbyWebCheckIn (app)┘
```

Dependencies only point right. DerbyCore knows nothing about SwiftUI or AppKit.

| Target | Holds |
| --- | --- |
| `DerbyCore` | `Racer`, `RaceGroup`, `EventData`; every check-in rule (`Rules.swift`); GPRM roster import and export (`Roster.swift`). Foundation only. |
| `DerbyKit` | `Store` (saving `event.json`, the data folder, photos, selection), the import and export panels, and the Settings window (General, Race Groups, Storage). |
| `DerbyCheckIn` | The native window: racer list, racer form, camera. |
| `DerbyWebCheckIn` | The host window, an HTTP server on Network.framework (`HTTPServer.swift`), the JSON API (`WebAPI.swift`) and the browser app (`Web/`). |

## Rules live in one place

Every automatic follow-up to an edit (car name limit, weight check, auto-pass, group name
and next number) is `EventData.applyingEditRules(_:was:)`. The Mac form gets it through
`Store.binding(_:)`; the web server calls it in `PATCH /api/racers/:id`. Group actions
(`renameRank`, `deleteGroup`, `renumber`, …) return a message for the user instead of
setting UI state, so each app shows it where it belongs.

The browser repeats only display logic (sorting, labels). It never decides a rule; it shows
the `problems` the server sends with every state.

## Concurrency

Swift 6 language mode, zero warnings. Everything UI-facing (`Store`, the views,
`ServerController`, `CameraModel`, `HTTPServer`'s start and stop) is on the main actor. Two
things run off it, each on its own serial queue:

- `HTTPConnection` (web server): Network.framework callbacks. Requests reach `WebAPI` through
  an `@Sendable` handler that awaits the main actor.
- `CaptureEngine` (camera): every `AVCaptureSession` change. Results come back through
  `@Sendable` callbacks that hop to the main actor with `Task { @MainActor in … }`.

A closure handed to a queue or framework callback is marked `{ @Sendable in … }`, so it can't
silently inherit the main actor and crash when it runs elsewhere. After any concurrency
change, run every background path once: `Tools/check-all.sh` covers the server, and
DerbyCheckInTests covers the camera queue.

## Data

- One folder per app: `~/Documents/Derby Check-In` and `~/Documents/Derby Web Check In`,
  movable to OneDrive, Google Drive or any folder in Settings › Storage.
- `event.json` (pretty-printed, ISO dates, written atomically 0.4 s after the last change)
  and `Photos/` (JPEG, longest side 1200 px, a new file name on every change).
- New properties need defaults and tolerant decoding, so older `event.json` files still open
  (see `RaceGroup.init(from:)` and `EventData.fillDefaultStartNumbers()`).

## Checks

```bash
Tools/check-all.sh                       # unit tests + web API test, made-up sample roster
Tools/check-all.sh ~/Desktop/Rosters.csv # the same with a real roster, plus its export fingerprint
```

- `swift test`: DerbyCoreTests (rules, rosters, groups), DerbyKitTests (Store, photos,
  export folder, storage moves) and DerbyCheckInTests (camera queue). Tests use `Tests/Fixtures/sample-roster.csv`, never real
  racers' names, and temporary folders, never the real event.
- `Tools/api-test.py`: drives the web API like a browser against a test server on port 8099.

## Build

`./build.sh` builds both apps into `build/` and copies `Sources/DerbyWebCheckIn/Web` into the
web app's bundle. `Tools/make-icon.swift` draws both icons (`--web` adds the Wi-Fi symbol).

## Undo

The Mac app's main window gives its undo manager to `Store`. Every change to `data` registers
an undo step that restores the previous event (and a redo step on the way back). Changes less
than a second apart join one step, so typing a name is one step; `Store.undoable(_:_:)` makes
an action its own named step ("Undo Check In Robin Avery"). Photo files are never deleted when
a racer or photo is removed, so Undo can bring them back; files unused for a day are cleared
at the next launch. The web app has no undo manager, so nothing is recorded there.

## Snapshots

```bash
DERBY_SNAPSHOTS=/tmp/derby-shots swift test --filter SnapshotTests
```

draws the racer form and each Settings tab, light and dark, to PNG files using the sample
roster, without the screen or any permission.
