# Module 2 — Source Scanning & Incremental Comparison

**Status:** Scoped, ready to build
**Depends on:** Module 1 (Source & Target Selection) complete and passing
**Blocks:** Module 3 (Copy Engine)
**Last Updated:** 2026-04-21

> Before building this module, read `00_OVERALL_DIRECTIVE.md` in full.
> This document covers Module 2 only.

---

## What This Module Does

Module 2 runs immediately after Module 1 hands off a confirmed source and target.

Its job is to answer one question for every file in the source: **"Do we already have
a verified copy of this at the target?"**

The output is a `ScanResult` — a categorised list of every source file tagged as either
Skip (already backed up and verified) or Copy (needs to be copied). This list is handed
to Module 3. Module 2 never copies, moves, or modifies any file.

---

## File Status Categories

Every source file ends up in exactly one category:

**Skip** — do not copy. Criteria (all must be true):
1. The file's destination path exists at the target.
2. A verified database record exists for this file under this source/target pair.
3. The destination file's current size matches the stored record.

We trust the database for files that have a verified record and a size-matched destination
file. We do not re-hash destination files on every scan — that would defeat the purpose
of incremental backup. Re-hashing is reserved for an explicit "Deep Verify" action
(future feature, not Module 2's concern).

**Copy** — needs to be copied. Any of these conditions triggers it:
- No destination file exists.
- No database record exists (file was never backed up via this app, or DB was cleared).
- Destination file exists but its size doesn't match the stored record (possible corruption
  or truncated partial copy from a previous interrupted session).

There is no "verify-only" category at scan time. If the database has no record, the file
is treated as needing a copy. This is the conservative, correct default.

---

## Destination Path Computation

The destination path for any source file is computed as:

```
[target root] / [session folder] / [relative path from source root]
```

**For camera card sources:**
The session folder is the card's `destinationFolderName` stored in `KnownCard`
(e.g. `20260421_EOS R6 Mark III Card-1`).

Example:
```
Source root:  [card]/
Source file:  DCIM/100EOSR6/_MG_1530.CR3
Session folder: 20260421_EOS R6 Mark III Card-1
Destination:  [target]/20260421_EOS R6 Mark III Card-1/DCIM/100EOSR6/_MG_1530.CR3
```

Root-level files (e.g. `.CSD` settings files) are handled the same way:
```
Source file:  CDEFAULT.CSD
Destination:  [target]/20260421_EOS R6 Mark III Card-1/CDEFAULT.CSD
```

**For generic folder sources (non-card):**
The session folder is the source folder's name.

Example:
```
Source root:  /Files/WorkingFiles/
Session folder: WorkingFiles
Destination:  [target]/WorkingFiles/[relative path]
```

`DestinationPathService` is responsible for this computation. It takes a source URL,
the source root URL, and the session folder name, and returns the destination URL.
It must never be called from a View.

---

## File Exclusion Rules

The following files are silently excluded from the scan and never copied.
These are macOS filesystem artifacts that cameras do not create:

- `.DS_Store` — macOS Finder metadata
- Files beginning with `._` — macOS resource fork files
- `.Spotlight-V100` — Spotlight index
- `.Trashes` — macOS trash folder
- `.fseventsd` — macOS filesystem event log

These patterns are defined as a constant (`excludedFilenames`) in `Constants.swift`,
not hardcoded into the scanner. Adding a new exclusion should require changing one line.

Directories matching these names are also excluded (not descended into).

---

## Scan Performance

A full camera card may contain thousands of files totalling hundreds of gigabytes.
The scan must remain responsive at all times.

**Enumeration** — `FileManager.enumerator(at:includingPropertiesForKeys:)` is the
right Apple API. Request only the keys needed: `fileSize`, `isDirectory`,
`isRegularFile`, `isHidden`. Do not request more than needed — each key has a cost.

**Database comparison** — do not query the database once per file. Instead:
1. Enumerate all source files into memory first (fast — just paths and sizes).
2. Fetch all database records for this source/target pair in a single batch query.
3. Compare in memory. This scales to thousands of files without performance issues.

**Run on a background Task** — never on the main thread. Post progress updates via
`@Published` properties on `ScanViewModel` so the UI stays responsive.

**Progress reporting** — update the UI with a running file count as enumeration
proceeds. The user should see numbers climbing, not a frozen screen.

---

## Settings File Tagging

During the scan, any file matching the camera settings pattern for the detected camera
model is tagged as a settings file in the `SourceFile` record. This tag is stored in
the database when the file is later copied, enabling the stretch goal (§9.1).

**Canon EOS R6 Mark III:** `*.CSD` at source root level.

The tagging rules live in `SettingsFilePatterns.swift` — a lookup table keyed by
camera model string. The scanner consults this table; it does not contain camera-
specific logic itself.

```swift
// SettingsFilePatterns.swift
// Maps camera model strings to the file patterns that identify settings files.
// Add new cameras here as they are encountered and tested.
static let patterns: [String: SettingsFilePattern] = [
    "Canon EOS R6 Mark III": SettingsFilePattern(
        extensions: ["CSD"],
        mustBeAtSourceRoot: true
    )
    // Additional cameras added here over time
]
```

If no pattern exists for the detected camera model, files are not tagged as settings
files. This is safe — the stretch goal simply won't have settings to restore for that
camera until a pattern is added.

---

## Scan Summary Screen

After scanning, before handing off to Module 3, the app presents a summary screen.
The user must confirm before copying begins. This is the last decision point.

The summary shows:
- **Files to copy:** count and total size (e.g. "47 files — 12.4 GB")
- **Already backed up:** count (e.g. "234 files — skipping")
- **Excluded:** count of system files silently skipped (e.g. "3 system files excluded")
- **Target available space:** current figure with warning if under threshold
- **"Start Backup"** button — prominent
- **"Cancel"** button — returns to Module 1 selection screen

If there is nothing to copy (all files already verified):
- Show a clear "Everything is already backed up" message.
- Do not show a "Start Backup" button. Show "Done" instead.
- This is a success state, not an error. It should feel reassuring, not anticlimactic.

---

## Files To Build

```
VirtualBackupBox/
├── Models/
│   ├── SourceFile.swift          ← single scanned file: URL, relative path, size,
│   │                                status (skip/copy), isSettingsFile flag
│   └── ScanResult.swift          ← aggregate: arrays of skip/copy files, counts,
│                                    total bytes to copy, excluded count
├── Services/
│   ├── SourceScannerService.swift    ← walks source tree, applies exclusions,
│   │                                    fetches DB records, categorises each file
│   ├── DestinationPathService.swift  ← computes destination URL from source URL
│   │                                    + source root + session folder name
│   └── SettingsFilePatterns.swift    ← lookup table: camera model → file patterns
├── ViewModels/
│   └── ScanViewModel.swift       ← orchestrates scan, exposes progress + result,
│                                    no UI logic
└── Views/
    └── Scan/
        ├── ScanProgressView.swift    ← "Scanning… X files found" while scan runs
        └── ScanSummaryView.swift     ← summary + confirm/cancel before copy begins
```

No file should exceed ~200 lines. If `SourceScannerService` grows large, extract the
database comparison logic into a separate `ScanComparisonService`.

---

## SwiftData Queries

Module 2 reads from the database but does not write to it. Writing happens in Module 4
(Verification) after a file has been successfully copied and verified.

The `FileRecord` model is defined in full in `00_DATA_MODELS.md` — read that document
before building this module. All four SwiftData models should be created in the Xcode
project before any module build begins (see build order at the end of `00_DATA_MODELS.md`).

The query needed:

```swift
// Fetch all FileRecord entries for a given source root path and target root path.
// Returns a dictionary keyed by relative source path for O(1) lookup during comparison.
// Uses absoluteSourceRoot to scope the query to this source only.
func fetchVerifiedRecords(
    sourceRoot: String,
    targetRoot: String,
    context: ModelContext
) -> [String: FileRecord]
```

Module 2 must not write or modify any database record. It reads `FileRecord`; it does
not create or update them.

---

## Key Constraints & Cautions

**The scan is read-only.** Module 2 must not create directories, write files, or
modify the database. It observes only.

**File enumeration includes root-level files.** The Canon card has `.CSD` files at the
card root, not inside any subfolder. `FileManager.enumerator` handles this correctly
when started at the source root — root-level files are included in the first level of
enumeration. Confirm this in testing.

**Empty source is valid.** A freshly formatted card may have no media files. The scan
result will show zero files to copy. The summary screen should handle this gracefully
(it may trigger the settings-restore stretch goal prompt in a future version).

**Symbolic links are not followed.** Pass `options: [.skipsSubdirectoryDescendants]`
only where appropriate. Do not follow symlinks — camera cards do not contain them and
following them on arbitrary folder sources could produce infinite loops.

**Large files do not block enumeration.** Enumeration reads file metadata only — it
never reads file content. File content is read by Module 3 during copy and Module 4
during verification. Keep Module 2 strictly metadata-only.

---

## Open Questions for This Module

| # | Question | Status |
|---|----------|--------|
| 1 | "Deep Verify" mode (re-hash all destination files on demand) | ❓ Future feature — not Module 2. Note the architecture here so Module 2 can be extended without rewrite. |
| 2 | What if source root has no DCIM and no known session folder? | ✅ Use source folder name as session folder. Simple, no special logic needed. |

---

## Definition of Done

Module 2 is complete when:
- [ ] Scanner correctly enumerates all files in a source folder including root-level files.
- [ ] All exclusion patterns (`.DS_Store`, `._*`, etc.) are applied and excluded files
      are counted but not included in the copy list.
- [ ] Settings files are correctly tagged for the Canon EOS R6 Mark III (`.CSD` at root).
- [ ] Database comparison is done via a single batch fetch, not per-file queries.
- [ ] Files with verified database records and matching destination size are marked Skip.
- [ ] All other files are marked Copy.
- [ ] Destination paths are computed correctly for both card and generic folder sources.
- [ ] Scan runs on a background Task; UI remains responsive throughout.
- [ ] Summary screen shows correct counts, sizes, and available space.
- [ ] "Everything already backed up" state is handled gracefully and feels like success.
- [ ] Tested against the Sample Camera Card in the planning workspace.
- [ ] No file exceeds ~200 lines.
