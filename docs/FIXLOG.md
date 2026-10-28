# Fix log

## 2026-10-27: Storage tab could miss that the event is in OneDrive

`CloudFolder.service(of:in:)` compared folder paths as plain text. macOS shows the same
folder as `/var/...` or `/private/var/...`, so a match could fail, and `OneDrive-Personal`
would also have matched a sibling folder named `OneDrive-Personal-Old`. Found while moving
the storage self-test into `swift test`. Now both paths are normalized and must match on a
whole folder name.

Rule: compare file locations with normalized paths and a trailing `/`, never a raw `hasPrefix`.

## 2026-10-27: Web page didn't show "Not inspected" for a car nobody had inspected

The server leaves an empty inspection result out of its JSON, so the browser saw `undefined`
where it compared against `null`, and no choice was selected. Found while checking the new
radio buttons on screen. The page now treats a missing result as Not inspected.

Rule: in the browser, read an optional the server may omit with `?? null` before comparing.

## 2026-10-28: Undo tests crashed now and then

The Undo tests ended each simulated click by spinning the main run loop so the undo manager
would close that step's group. With nothing scheduled, the run loop can return without a pass,
so two steps sometimes merged; undoing then removed the whole racer and the next line read a
racer that wasn't there. The app itself was fine: every real event closes its group. Each test
step now schedules a tiny timer so the pass always happens, checks the group closed, and reads
racers with `#require` so a missing one fails the test instead of crashing the run.

Rule: to end an undo group in a test with groupsByEvent, run one real run-loop pass (schedule a
timer first); never call endUndoGrouping on the automatic group.
