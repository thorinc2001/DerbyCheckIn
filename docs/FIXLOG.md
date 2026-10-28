# Fix log

## 2026-10-27: Storage tab could miss that the event is in OneDrive

`CloudFolder.service(of:in:)` compared folder paths as plain text. macOS shows the same
folder as `/var/...` or `/private/var/...`, so a match could fail, and `OneDrive-Personal`
would also have matched a sibling folder named `OneDrive-Personal-Old`. Found while moving
the storage self-test into `swift test`. Now both paths are normalized and must match on a
whole folder name.

Rule: compare file locations with normalized paths and a trailing `/`, never a raw `hasPrefix`.
