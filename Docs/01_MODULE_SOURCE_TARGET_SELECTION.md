# Module 1 — Source & Target Selection

**Status:** Scoped, ready to build
**Depends on:** Nothing (this is the entry point for every session)
**Blocks:** Module 2 (Source Scanning), all subsequent modules
**Last Updated:** 2026-04-21

> Before building this module, read `00_OVERALL_DIRECTIVE.md` in full.
> This document covers Module 1 only. Do not build Module 2 behaviour here.

---

## What This Module Does

Module 1 is the front door of the app. Every backup session starts here.

Its job is to establish two things before any copying can begin:
1. **Source** — what folder are we backing up from?
2. **Target** — what folder are we backing up to?

Once both are confirmed and accessible, the module hands off to Module 2.
It does not scan, copy, or verify anything itself.

---

## User-Facing Behaviour

### The Main Screen

The app opens to a single screen showing two zones: Source and Target.

**Target zone** (shown first — it's the more persistent of the two):
- If a known target is connected/available: show its name and a green "connected" indicator.
  No action required from the user.
- If no known target is available: show a prompt to select or connect one.
- A "Manage Targets" affordance lets the user add, remove, or rename saved targets.
- If available space on the target is under 2 GB (`minimumWarningSpaceBytes` in
  `Constants.swift`), show a visible warning. The "Start Backup" button remains enabled
  — this is a warning, not a block. iCloud Drive targets show iCloud quota remaining.

**Source zone:**
- Always shows a "Select Source" button — source is never auto-selected.
- After selection, shows the source name (card friendly name, or folder path for
  non-card sources) and a brief summary (e.g. "Canon EOS R6 Mark III Card-1").
- If the selected source is a known card, shows when it was last backed up.

**Go button:**
- Disabled until both source and target are selected and accessible.
- Tapping it hands off to Module 2 (scanning).
- Label: "Start Backup" (not "Go", "Copy", or "Sync" — "Backup" is the clearest word
  for this audience).

### Selecting a Source

Tapping "Select Source" opens the system document picker in folder-selection mode.
The user navigates to and selects the source folder (card root, or any folder).

After selection, the app immediately:
1. Checks whether the selected folder contains a `DCIM` subfolder at its root.
   - Yes → treat as a camera card. Proceed to Card Detection flow (below).
   - No → treat as a generic folder. Skip card detection. Show folder path as source name.
     Proceed directly to the ready state.

### Card Detection Flow

Triggered when the selected source folder contains `DCIM/` at its root.

**Step 1 — Read volume UUID**
Read `URLResourceKey.volumeUUIDStringKey` from the selected folder's URL.
If the UUID cannot be read (unusual but possible for some FAT32 volumes), fall back to
treating the source as a generic folder. Do not block the user.

**Step 2 — Check if card is known**
Look up the UUID in the `KnownCard` database.
- **Known card** → skip to Ready State. Show card name, camera model, last backup date.
- **Unknown card** → proceed to Step 3.

**Step 3 — Read camera name**
Try to extract camera make/model from media files on the card:
1. Find any `.CR3` or `.JPG` file in `DCIM/` and read it with `ImageIO`.
2. If no stills, find any `.MP4` in `XFVC/` and read it with `AVFoundation`.
3. If no media files at all (empty/freshly formatted card), leave camera name blank.

The camera name string to use is the `Model` field from EXIF/metadata
(e.g. "Canon EOS R6 Mark III"). Do not include "Make" — model alone is sufficient
and more compact.

**Step 4 — Card Naming Dialog**
Present a modal dialog (cannot be dismissed without completing it) containing:
- A text field pre-filled with the suggested name (see Suggested Name logic below).
- A camera model field pre-filled with the extracted model name (editable).
- "Confirm" button — saves the card record and proceeds.

**Suggested Name logic:**
- Count how many `KnownCard` records exist with the same `cameraModel` string.
- Suggest: `[Model] Card-[N+1]` (e.g. "EOS R6 Mark III Card-2").
- If no camera model was found: suggest "Card-[total card count + 1]".

**What gets saved to the database on confirm:**
- `uuid` — the volume UUID (primary key, never changes for this card generation)
- `friendlyName` — the user-confirmed name (e.g. "EOS R6 Mark III Card-2")
- `cameraModel` — the confirmed camera model string (e.g. "Canon EOS R6 Mark III")
- `destinationFolderName` — computed as `YYYYMMDD_[friendlyName]` using today's date
- `firstSeenDate` — today

### Selecting or Managing Targets

**First-time target selection:**
Tapping "Select Target" (or "Add Target" from the manage screen) opens the system
document picker. The user selects the destination folder (the root of their backup
drive, or any folder).

On selection, the app:
1. Creates a security-scoped bookmark for the selected URL. Store as `Data`.
2. Prompts the user for a friendly name (e.g. "Samsung T7", "Vacation Drive").
   Pre-fill with the volume name if available (`URLResourceKey.volumeNameKey`).
3. Saves a `KnownTarget` record to the database.

**Subsequent sessions:**
On app launch, the app attempts to resolve each stored `KnownTarget` bookmark.
- Bookmark resolves and volume is accessible → mark as available, show in Target zone.
- Bookmark resolves but volume not mounted → mark as unavailable (drive not plugged in).
- Bookmark fails to resolve → mark as stale (drive may have been reformatted or renamed).

The Target zone shows the first available known target automatically. If multiple known
targets are available, the user can switch between them via the Manage Targets screen.

**Manage Targets screen:**
A simple list of known targets showing name, availability status, and last-used date.
Actions per target: rename, remove. No reorder needed.

---

## Ready State

Both source and target are confirmed. The main screen shows:
- Source: card/folder name, camera model (if card), last backup date (if known card)
- Target: drive name, available space
- "Start Backup" button — prominent, tappable

No other action is required from the user. This state is the handoff point to Module 2.

---

## Files To Build

Follow §6.3 (one file, one job). Every file needs a header comment and per-function
plain-English explanations per §6.2.

```
VirtualBackupBox/
├── Models/
│   ├── KnownCard.swift         ← SwiftData model for known camera cards
│   └── KnownTarget.swift       ← SwiftData model for known backup targets
├── Services/
│   ├── CardDetectionService.swift   ← reads UUID, detects DCIM, extracts camera name
│   └── BookmarkService.swift        ← creates, stores, and resolves security-scoped bookmarks
├── ViewModels/
│   └── SelectionViewModel.swift     ← orchestrates the full selection flow; no UI logic
└── Views/
    └── Selection/
        ├── SelectionView.swift       ← main screen: source zone + target zone + Start Backup
        ├── CardNamingDialog.swift    ← modal: name a new card before first backup
        └── ManageTargetsView.swift  ← list of known targets with add/remove/rename
```

No file should exceed ~200 lines. If any file approaches that limit, stop and split it.

---

## SwiftData Models

### KnownCard

```swift
// Represents one generation of a physical camera card.
// A reformatted card gets a new UUID and a new KnownCard record.
@Model class KnownCard {
    var uuid: String                  // volume UUID — the primary identifier
    var friendlyName: String          // user-assigned, e.g. "EOS R6 Mark III Card-1"
    var cameraModel: String           // e.g. "Canon EOS R6 Mark III" — stored explicitly
    var destinationFolderName: String // e.g. "20260421_EOS R6 Mark III Card-1"
    var firstSeenDate: Date
    var lastBackupDate: Date?
    // Relationship to CopySession records added in Module 6
}
```

### KnownTarget

```swift
// Represents a known backup destination folder.
// Persisted via security-scoped bookmark so the app can reconnect without user action.
@Model class KnownTarget {
    var friendlyName: String    // user-assigned, e.g. "Samsung T7"
    var bookmarkData: Data      // security-scoped bookmark for persistent access
    var addedDate: Date
    var lastUsedDate: Date?
    // isAvailable is computed at runtime by resolving the bookmark — not stored
}
```

---

## Key Constraints & Cautions

**Security-scoped bookmarks require `startAccessingSecurityScopedResource()` / 
`stopAccessingSecurityScopedResource()` calls.** Always call stop when done, including
on error paths. A `defer` block is the right pattern. Forgetting this is a resource leak.

**The system document picker returns a security-scoped URL.** The app must call
`startAccessingSecurityScopedResource()` on it immediately and hold access for the
duration of the session. For the source (transient), stop access when the session ends.
For the target (persistent), the bookmark replaces the need to hold the original URL.

**Volume UUID may be nil on some FAT32 cards.** Handle gracefully — fall back to
generic folder treatment. Do not crash or block.

**Camera name extraction touches the file system and may be slow on large files.**
Run it on a background Task, not on the main thread. Show a brief "Reading card..."
indicator while it runs.

**The naming dialog is blocking by design.** A new card cannot be backed up without
being named. This is intentional — the name drives the destination folder structure,
and that folder must exist before Module 2 runs.

---

## Open Questions for This Module

| # | Question | Status |
|---|----------|--------|
| 1 | iCloud Drive as a target | ✅ In scope. Treated as any other folder — document picker returns a URL, copy engine doesn't distinguish. iCloud eviction is expected and desirable. |
| 2 | Available space warning threshold | ✅ Decided. Use `volumeAvailableCapacityForImportantUsageKey` as a soft warning only. Never block a session on this number. Handle actual "disk full" via retry-then-skip (§5c). Show a warning banner if available space is under 2 GB, but allow the user to proceed. The 2 GB threshold is a named constant (`minimumWarningSpaceBytes`) defined in `Constants.swift`. |

---

## Definition of Done

Module 1 is complete when:
- [ ] Tapping "Select Source" opens the system picker; selecting a non-DCIM folder
      shows it as source with no card features activated.
- [ ] Selecting a folder containing `DCIM/` triggers card detection; UUID is read;
      known cards are recognised without a naming dialog; unknown cards show the dialog.
- [ ] The naming dialog pre-fills camera model from EXIF/metadata and suggests a name.
      Confirmed details are saved to SwiftData.
- [ ] At least one known target can be saved, bookmarked, and auto-reconnected on
      next launch with the drive plugged in.
- [ ] The "Start Backup" button is disabled until both source and target are active.
- [ ] All of the above works on iPad (primary) and iPhone (secondary).
- [ ] No file exceeds ~200 lines. No UI logic in ViewModels. No business logic in Views.
