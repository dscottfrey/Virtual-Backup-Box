# Module 6 — Results & History

**Status:** Scoped, ready to build
**Depends on:** Module 4 (FileRecord written), Module 5 (session complete)
**Blocks:** Nothing — this is the final module
**Last Updated:** 2026-04-21

> Before building this module, read `00_OVERALL_DIRECTIVE.md` and `00_DATA_MODELS.md`.
> This module has two faces: the post-session results screen and the persistent
> history browser. Both read from SwiftData; neither writes except for cleanup
> and the source-deletion feature.

---

## What This Module Does

Module 6 has two distinct jobs that share the same data:

**1. Post-Session Results Screen**
Shown immediately when a session ends (success, partial success, or interrupted).
Gives the user a clear, unambiguous account of what happened. This is the last
screen of every backup session.

**2. History Browser**
A persistent screen accessible at any time from the app's main navigation.
Shows all past sessions, lets the user inspect what was backed up, manage stored
records, and purge stale entries.

---

## Part A: Post-Session Results Screen

### When It Appears

`BackupSessionService` posts the completed `CopySession` to `SessionViewModel` when
the session ends. The app navigates automatically from the progress screen (Module 5)
to the results screen. The user does not need to tap anything to get here.

### Three Outcome States

**Success — all files verified**

The primary visual is a large, calm confirmation. Not a celebration — a reassurance.
Something was trusted to this app and it delivered. The tone is "done, confirmed."

- Clear heading: "Backup Complete"
- Summary line: "47 files — 18.7 GB — all verified" 
- Secondary line: "234 files were already backed up and skipped"
- Destination shown: "Backed up to: Samsung T7 › 20260421_EOS R6 Mark III Card-1"
- Session duration: "Completed in 4 minutes 12 seconds"
- If source was internal iPad storage: show the cleanup offer (see below)
- "Done" button — returns to the main selection screen (Module 1)

**Partial Success — some files failed**

- Heading: "Backup Completed with Warnings"  
- Summary: "44 of 47 files backed up — 3 files could not be copied"
- Failed files listed explicitly, each with its name and failure reason.
  This list is scrollable if there are many failures.
- "What should I do?" — a plain-English explanation: "These files were not backed up.
  The files that succeeded are safely stored. You may want to try running the backup
  again — the app will attempt only the files that failed."
- "Done" button

**Interrupted — session was cancelled or card removed**

- Heading: "Backup Interrupted"
- Summary: "12 of 47 files backed up before the session stopped"
- Plain-English explanation: "Files that were successfully backed up before the
  interruption are safely stored. Run the backup again to continue — the app will
  skip files that are already done."
- "Done" button

### Source Cleanup Offer (Internal iPad Storage Only)

Shown only when:
1. Session outcome is **Success** (not partial, not interrupted)
2. Source was internal iPad storage (not a camera card, not an external drive)

The offer appears as a secondary section below the success summary:

```
─────────────────────────────────────────
Remove from iPad storage?

All 47 files have been verified on Samsung T7.
You can remove them from iPad storage to free up space.

[Remove from iPad]    [Keep on iPad]
─────────────────────────────────────────
```

Tapping "Remove from iPad":
1. Shows a confirmation sheet: "This will permanently delete 47 files (18.7 GB)
   from your iPad. This cannot be undone. The files are safely stored on Samsung T7."
   With "Delete Files" (destructive, red) and "Cancel" buttons.
2. On confirm: delete the source files via `FileManager.removeItem`. 
3. Log the deletion in the `CopySession` record (`sourceFilesDeleted = true`).
4. Show a brief confirmation: "18.7 GB removed from iPad storage."

This deletion is the **only time the app writes to the source**. It is initiated
entirely by explicit user confirmation. Add a comment at every callsite noting this
is the deliberate exception to the read-only source rule (§2 of overall directive).

---

## Part B: History Browser

### Navigation

Accessible from the main selection screen (Module 1) via a history button —
a clock or document icon, top trailing. The history browser is a modal sheet or
a navigation push, depending on iPad/iPhone context.

### Session List

Sessions are listed in reverse chronological order (most recent first).
Each session row shows:
- Card name or source folder name (bold)
- Target name
- Date and time
- Outcome icon: ✓ (success), ⚠ (partial), ✕ (interrupted)
- File count and total size

Grouped by source card/folder, with the most recently used at the top of each group.
Grouping makes it easy to see the history of a specific card.

### Session Detail View

Tapping a session row shows its detail:
- All summary information from the row
- Session duration
- List of files: successful (default collapsed — can be expanded), failed (always shown)
- Failed files show their failure reason
- For sessions with `sourceFilesDeleted = true`: a note "Source files were removed
  from iPad storage after this backup"

### Database Cleanup

Two cleanup triggers, both requiring user confirmation. Neither is automatic.

**User-initiated (manual):**
A "Clear History" button in the history browser. Options:
- "Clear all history" — deletes all `CopySession` and `FileRecord` entries.
  Does not delete `KnownCard` or `KnownTarget` records — those represent
  known hardware, not session history.
- "Clear sessions older than..." — 30 days, 90 days, 1 year (picker).

**Opportunistic (on opening history browser):**
When the history browser opens, the app checks each session's `targetPath` and
`sourcePath` for accessibility. Sessions whose target volume is no longer
mountable are flagged "Destination unavailable" in the list. The app offers
(does not force) to remove these stale sessions via a banner:
"3 sessions reference drives that are no longer available. Remove them?"

Stale sessions are identified, not silently deleted. The user decides.

### KnownCard Management

A "Known Cards" section in the history browser (or a separate screen accessible from
it) lists all `KnownCard` records:
- Card name, camera model, first seen date, last backup date
- Session count for this card
- "Rename" action — updates `friendlyName`. Does not rename the folder on disk —
  the folder name is fixed at first-backup time (`destinationFolderName`).
- "Remove" action — deletes the `KnownCard` and its session history. Shows a warning
  that this removes the backup history but does not delete any files on disk.

---

## Files To Build

```
VirtualBackupBox/
├── Models/
│   └── (no new models — reads CopySession, FileRecord, KnownCard from 00_DATA_MODELS.md)
├── ViewModels/
│   ├── ResultsViewModel.swift      ← wraps the completed CopySession, computes
│   │                                  display strings, manages cleanup offer state
│   └── HistoryViewModel.swift      ← fetches and groups sessions from SwiftData,
│                                      manages stale session detection, cleanup actions
└── Views/
    └── Results/
        ├── SessionResultsView.swift     ← post-session screen: outcome heading,
        │                                  summary, failed file list, cleanup offer,
        │                                  Done button
        ├── CleanupOfferView.swift       ← the "Remove from iPad?" section with
        │                                  confirmation sheet; isolated so its
        │                                  deletion logic stays contained
        ├── HistoryBrowserView.swift     ← session list, grouped, with stale banner
        ├── SessionDetailView.swift      ← full detail for one session
        └── KnownCardsView.swift         ← card management: rename, remove
```

---

## SwiftData Queries

All reads use SwiftData `@Query` macro or explicit `ModelContext.fetch()`.

`HistoryViewModel` uses:
```swift
// All sessions, newest first
@Query(sort: \CopySession.startDate, order: .reverse) var sessions: [CopySession]
```

For grouping by source card/folder, group in the ViewModel after fetch —
do not attempt SQL-style grouping through SwiftData predicates. Grouping in
memory on a list of sessions is fast and simple.

For stale session detection — check `FileManager.default.isReadableFile(atPath:)`
on `session.targetPath` for each session. Do this on a background Task, not on
the main thread. Post results back to the ViewModel.

---

## Key Constraints & Cautions

**Source deletion is the only write to the source in the entire app (§2).**
Every line of code that touches source file deletion must have a comment:
```swift
// DELIBERATE EXCEPTION to read-only source rule (§2 of overall directive).
// This deletion is triggered only by explicit user confirmation after a
// 100% successful backup session. See SessionResultsView cleanup offer.
```

**"Clear History" does not delete KnownCard or KnownTarget records.**
These represent physical hardware the user has registered. History is session data.
They are separate concerns. Deleting history should never cause the app to "forget"
a drive or card that the user has named.

**The results screen must not be skippable.** After a session ends, the user lands
on the results screen. There is no auto-navigation back to the main screen — the
user taps "Done" when they are satisfied they have read the outcome. This is
intentional: the result of a safety-critical operation should require acknowledgement.

**Stale session detection is offered, not forced.** The app never silently deletes
session records. If it detects stale sessions, it surfaces them and lets the user
decide. A session record whose target drive is gone is still a historical record
of what was copied.

**Rename does not rename the folder on disk.** `KnownCard.friendlyName` is the
display name in the app. `KnownCard.destinationFolderName` is the physical folder
name on disk — it is set once at first backup and never changes. This avoids
breaking incremental comparison (which uses paths) if the user renames a card.

---

## Open Questions for This Module

| # | Question | Status |
|---|----------|--------|
| 1 | Should history be searchable? | ❓ Defer to v2. Not needed for initial use case. |
| 2 | Export session log as a text file? | ❓ Potentially useful. Defer to v2 — implement only if a real need is identified in use. |
| 3 | Should KnownTarget have a management screen too? | ✅ Yes — "Manage Targets" is already in Module 1's spec. Link to it from History browser rather than duplicating. |

---

## Definition of Done

Module 6 is complete when:
- [ ] Post-session results screen shows correct outcome for all three states:
      success, partial success, interrupted.
- [ ] Failed files are listed by name with their failure reason. List is scrollable.
- [ ] Cleanup offer appears only after a 100% successful session with an internal
      iPad storage source. Confirmation sheet is shown before any deletion.
- [ ] Deletion logs `sourceFilesDeleted = true` on the session and shows confirmation.
- [ ] History browser lists all sessions in reverse chronological order, grouped
      by source card/folder.
- [ ] Stale session detection runs on background Task when history opens.
      Stale sessions are flagged; cleanup is offered, not forced.
- [ ] Session detail view shows file list with success/failure status per file.
- [ ] KnownCard management: rename updates display name only (not folder on disk).
      Remove deletes card record and session history with warning.
- [ ] "Clear History" removes CopySession and FileRecord entries only.
      KnownCard and KnownTarget records are untouched.
- [ ] All source-deletion callsites have the required exception comment (§2).
- [ ] No file exceeds ~200 lines. No business logic in Views.
