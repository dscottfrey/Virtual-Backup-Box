# Module 5 — Progress & Status UI

**Status:** Scoped, ready to build
**Depends on:** Module 3 (`SessionViewModel` with `@Published` properties and `SessionPhase`)
**Blocks:** Nothing (UI only — runs concurrently with Modules 3 and 4)
**Last Updated:** 2026-04-21

> Before building this module, read `00_OVERALL_DIRECTIVE.md`,
> `03_MODULE_COPY_ENGINE.md`, and `04_MODULE_VERIFICATION.md`.
> This module is pure UI — all data comes from `SessionViewModel`.
> No business logic lives here.

---

## What This Module Does

Module 5 is the live window into a running backup session. It binds to `SessionViewModel`
and displays everything the user needs to know while files are being copied and verified:
what's happening right now, how far along the whole session is, and whether anything
has gone wrong.

It also owns the failure warning dialog — the prominent, blocking alert that appears
when a file fails after all retries are exhausted.

---

## Design Philosophy

This is a safety-critical tool. The UI should feel **calm and informative**, not busy.

- Large, readable numbers. The user should be able to glance at the screen from across
  a table and know whether the session is running normally.
- No animation for its own sake. Progress bars animate naturally as values change —
  that's sufficient.
- Failures must be impossible to miss. A failed file interrupts the user explicitly.
  It cannot scroll past unnoticed.
- The session is doing important work. Don't compete with it. The UI serves the session,
  not the other way around.

---

## Screen Layout (iPad — Primary)

The progress screen uses a two-region layout on iPad:

**Top region — Current File**
Shows what is happening right now:
- Phase label: "Copying" or "Verifying" (maps to `SessionViewModel.currentPhase`)
- File name (truncated in the middle if long: `_MG_1530…CR3` not `_MG_153…`)
- Per-file progress bar (bytes written or read / total bytes for this file)
- Percentage complete for this file
- File size in human-readable form (e.g. "31 MB", "384 MB")

**Bottom region — Session Overview**
Shows the overall session status:
- Large fraction display: "12 of 47 files" 
- Overall progress bar spanning the full width
- Bytes transferred / total bytes (e.g. "4.2 GB of 18.7 GB")
- Elapsed time and estimated time remaining
  - Estimate is computed from average bytes/second over the last 10 seconds.
    Named constant: `transferRateWindowSeconds = 10` in `Constants.swift`.
  - Do not show estimated time until at least 5 seconds of data exists.
    Show "Calculating…" until then.
  - Show "—" if rate cannot be computed (e.g. no bytes moved yet).
- Files already skipped (backed up from previous sessions): shown as a secondary
  count, not a progress bar. e.g. "234 already backed up — skipped"
- Cancel button — bottom trailing, secondary styling. Label: "Cancel Backup"

**iPhone — Compact Layout**
Stack the two regions vertically. Phase label and filename at top, per-file progress
bar, then session overview below. Omit estimated time remaining if space is tight
(it is the least critical piece of information).

---

## The Two Phases: Copying and Verifying

`SessionViewModel.currentPhase` drives the top region entirely:

```
.copying(fileName:, bytesWritten:, totalBytes:)
    → Phase label: "Copying"
    → Progress bar: bytesWritten / totalBytes

.verifying(fileName:, bytesRead:, totalBytes:)
    → Phase label: "Verifying"
    → Progress bar: bytesRead / totalBytes

.idle
    → Phase label: hidden
    → Progress bar: empty (shown briefly between files)
```

The transition from "Copying" to "Verifying" for the same file should feel natural —
the file name stays, the phase label changes, the progress bar resets to zero and
begins filling again. No animation is needed beyond the natural progress bar movement.

For small files (below `verificationProgressThresholdBytes` from `Constants.swift`),
verification happens too fast to show byte progress meaningfully. In that case, show
a brief "Verifying…" label with an indeterminate spinner instead of a progress bar.

---

## Failure Warning Dialog

When `BackupSessionService` exhausts all retries on a file, it posts the failure to
`SessionViewModel.pendingFailureAlert`. Module 5 watches this and presents a blocking
alert sheet.

The alert:
- **Title:** "File Could Not Be Backed Up"
- **Body:** The specific file name (full relative path, so the user knows exactly
  which file) and the failure reason in plain English. Examples:
  - "DCIM/100EOSR6/_MG_1530.CR3 — Could not be read from the source after 3 attempts."
  - "XFVC/REEL_0003/A_0003C048H260421_082509HN_CANON.MP4 — Verification failed: the
    copied file did not match the original."
- **Button:** "Continue Backup" — single button, the user must tap it to proceed.
  No "Cancel" option in the failure dialog itself — if the user wants to stop, they
  use the "Cancel Backup" button on the main screen after dismissing this.

The session is paused while the dialog is visible. `BackupSessionService` waits for
`SessionViewModel.failureAlertDismissed` before proceeding to the next file.

Do not queue multiple failure dialogs. If a second failure occurs while the first
dialog is still visible (unlikely but possible), queue it and show it immediately
after the first is dismissed.

---

## Files To Build

```
VirtualBackupBox/
└── Views/
    └── Session/
        ├── SessionProgressView.swift    ← main progress screen; binds to SessionViewModel;
        │                                  two-region layout (current file + session overview)
        ├── CurrentFileView.swift        ← top region: phase label, filename, per-file
        │                                  progress bar, percentage, file size
        ├── SessionOverviewView.swift    ← bottom region: fraction, overall progress bar,
        │                                  bytes transferred, time remaining, skip count,
        │                                  cancel button
        └── FailureAlertModifier.swift   ← ViewModifier that watches SessionViewModel
                                           for pendingFailureAlert and presents the
                                           blocking sheet; handles queuing
```

`SessionProgressView` composes `CurrentFileView` and `SessionOverviewView`.
It owns the `FailureAlertModifier`. It does not contain layout logic beyond
arranging its child views — layout lives in the child views.

---

## SessionViewModel Additions (from Module 3)

Module 3 defines `SessionViewModel`. Module 5 requires these properties to exist —
confirm they are present before building Module 5:

```swift
@Published var currentPhase: SessionPhase       // .copying / .verifying / .idle
@Published var filesCompleted: Int              // verified files this session
@Published var filesFailed: Int                 // failures this session
@Published var filesSkipped: Int                // already-verified files skipped
@Published var totalFiles: Int                  // total files in scan result
@Published var totalBytesWritten: Int64         // cumulative bytes copied + verified
@Published var totalBytesToProcess: Int64       // total bytes in files to copy
@Published var sessionElapsedSeconds: Double    // running timer
@Published var pendingFailureAlert: FailureAlert?  // non-nil when a file has failed
```

`FailureAlert` is a small struct:
```swift
struct FailureAlert: Identifiable {
    let id = UUID()
    let relativeFilePath: String
    let reason: String
}
```

---

## Formatting Helpers

File sizes and byte counts must be formatted consistently throughout the UI.
Use `ByteCountFormatter` (Apple's built-in formatter) — do not hand-roll byte
formatting. It handles KB/MB/GB correctly and respects locale.

Time remaining: format as "1h 23m", "4m 30s", or "< 1 minute". Do not show seconds
precision for durations over a minute — it creates false precision and flickers.

---

## Key Constraints & Cautions

**This module is pure UI — no business logic.** If you find yourself writing an
`if` statement that depends on file state rather than display state, it belongs in
`SessionViewModel` or `BackupSessionService`, not here.

**All `SessionViewModel` properties are `@MainActor`.** Bindings in SwiftUI Views
are already on the main thread, so this should be transparent. If you encounter
threading warnings, the fix is in the service layer (Module 3/4), not here.

**Middle-truncation for long filenames.** Canon video filenames like
`A_0003C048H260421_082509HN_CANON.MP4` are long and the meaningful parts are at
both ends (reel number at the start, timestamp in the middle). Use
`.lineLimit(1).truncationMode(.middle)` on the Text view — SwiftUI handles this.

**Do not use a Timer to update elapsed time.** Derive elapsed time from
`sessionStartDate` and `Date.now` on each view update. A `TimelineView` with a
`.periodic` schedule is the correct SwiftUI approach — it drives updates at a
regular interval without a manual Timer.

---

## Open Questions for This Module

| # | Question | Status |
|---|----------|--------|
| 1 | Should completed files scroll by in a list during the session? | ❓ Nice to have, adds complexity. Defer to v2. Show counts only in v1. |
| 2 | Sound or haptic on session completion? | ❓ A single subtle haptic on completion is appropriate. Use `UINotificationFeedbackGenerator` with `.success`. No sound — the user may be in a quiet environment. |

---

## Definition of Done

Module 5 is complete when:
- [ ] `SessionProgressView` displays correctly on iPad (primary) and iPhone (secondary).
- [ ] Phase label switches between "Copying" and "Verifying" as `SessionPhase` changes.
- [ ] Per-file progress bar fills correctly from `currentPhase` byte values.
- [ ] Overall progress bar reflects `filesCompleted / totalFiles` accurately.
- [ ] Bytes transferred and total display in human-readable form via `ByteCountFormatter`.
- [ ] Estimated time remaining appears after 5 seconds and updates smoothly.
- [ ] "234 already backed up — skipped" count is visible and correct.
- [ ] Failure alert appears immediately when `pendingFailureAlert` is set,
      blocking the session until dismissed. File name and reason are correct.
- [ ] Multiple queued failure alerts show sequentially, not simultaneously.
- [ ] "Cancel Backup" stops the session cleanly (via `BackupSessionService`).
- [ ] Completion haptic fires on session end.
- [ ] No business logic in any View file.
