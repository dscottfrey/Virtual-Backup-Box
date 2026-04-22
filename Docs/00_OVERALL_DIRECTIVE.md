# Virtual Backup Box — Overall Directive

**Status:** In Progress — being built collaboratively with Scott
**Last Updated:** 2026-04-21 (rev 2)
**Platform:** iPadOS 17+ (primary), iOS 17+ (secondary)
**Language:** Swift / SwiftUI

> This document is the authoritative spec for the entire app.
> Claude Code must read it at the start of every session before writing any code.
> When this document changes, Scott must sync the `Xcode Project Files/` folder
> into the Xcode project root so Claude Code is working from the current version.

---

## §1 — App Purpose

Virtual Backup Box is an **incremental verified backup** tool for photographers and
videographers working in the field — away from their home computer, mid-shoot, mid-day.

**The core mental model:** Every time you run the app, it looks at the source and asks
"what here do I not already have a verified copy of?" and copies only that. Running it
ten times against the same source is safe and efficient — mostly it will find nothing new
and finish in seconds. The user never has to think about what was already backed up.

### Source and Target Are Symmetric

The app is completely agnostic about storage media. **Any accessible folder can be the
source. Any accessible folder can be the target.** The copy-and-verify engine treats them
identically regardless of what storage medium they live on.

Examples of valid source → target combinations:
- Camera card → external SSD *(primary use case)*
- Camera card → VBB Internal Storage *(staging, when no drive is available)*
- Camera card → iCloud Drive *(direct to cloud)*
- Internal local storage → external SSD *(offload staged files)*
- Internal local storage → iCloud Drive *(offload staged files to cloud)*
- External SSD → second external SSD *(backup of a backup)*

### iCloud Drive as a Target

iCloud Drive is a fully supported target, not a special case. From the copy engine's
perspective it is just a folder — the document picker returns a URL, files are copied
there, checksums are verified. The app does not need to know or care whether a folder
lives on iCloud Drive or a local volume.

iCloud's "Optimize Storage" behaviour — evicting local copies to the cloud once synced
— is **desirable and expected**. After the app verifies a file was copied correctly
(checksum confirmed), iCloud is free to manage that file however it wishes. The
database record is proof the file was there and verified at time of backup.

### Post-Backup Source Cleanup

When a backup session completes with **100% success** (no failures, all files verified),
and the source was VBB Internal Storage, the app offers to remove the source files
from local storage. This is the intended workflow for users who use the device as a
staging area between card and cloud/drive:

1. Copy card → VBB Internal Storage (first safe copy)
2. Back up VBB Internal Storage → iCloud Drive or external SSD (verified backup)
3. App offers: "Remove from local storage?" — user confirms
4. App deletes the source files, freeing device space

This cleanup action is:
- **Never automatic.** Always requires explicit user confirmation.
- **Only offered on 100% success.** Any failure in the session and the offer is suppressed.
- **Destructive and logged.** The deletion is recorded in the session history.
- Implemented in Module 6 (Results & History), not the copy engine.

### Available Storage Space

iOS provides available capacity via `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`.
This number is used as a **soft warning only** — never as a hard gate that blocks a session.
Reasons: the number is approximate, iCloud available space is the remaining quota rather
than physically free space, and mid-copy "disk full" errors are already handled by the
retry-then-skip policy in §5c. If available space cannot be determined, the session
proceeds with no warning.

The camera-card-specific features — UUID detection, EXIF camera name reading, the
friendly name prompt, the dated destination folder — are **enhancements** that activate
when the app recognises a camera card volume. They are layered on top of the generic copy
engine, not the foundation of it. When the source is not a camera card, the app behaves
as a straightforward folder-to-folder incremental backup tool.

**What the app is not:** It is not a DAM (digital asset management) tool. It does not
organise, rename, keyword, or import files. It copies faithfully and verifies completely.
Organisation is the job of Lightroom, Capture One, or whatever the user prefers.

---

## §2 — Core Principles

- The app should feel calm and trustworthy. This is a safety-critical utility — users are
  trusting it with irreplaceable files. Confidence comes from clear feedback, not busy UI.
- Speed matters, but correctness matters more.
- The user should always know: what's happening, how far along it is, and whether it worked.
- Errors must be reported clearly and specifically — not buried or dismissed.
- **The source is always read-only.** The app never writes to, modifies, or deletes any
  file on the source. This applies to camera cards, internal storage sources, and drive
  sources equally. The one explicit exception is the settings restore stretch goal (§9.1),
  which writes camera settings files back to a card by deliberate user action — that
  exception must be clearly documented at every callsite where it occurs.

---

## §3 — Platforms and Deployment

- **Primary target:** iPad (iPadOS 17+). The UI should be designed for iPad first.
- **Secondary target:** iPhone (iOS 17+). Same codebase; layout adapts.
- File access via Apple's standard document picker / UIDocumentPickerViewController or
  equivalent SwiftUI API. No jailbreak, no private API.
- **One source card at a time.** The app does not handle multiple simultaneous sources.
  The workflow is: insert card → back up → done. Multi-card or concurrent copy is
  explicitly out of scope.

### Source & Target Access Model

**Source:** Always selected fresh each session via the system folder/document picker.
Sources are treated as transient — a card gets ejected, a drive gets swapped. The app
does not persist source access between sessions.

**Target:** Treated as a persistent, known location. On first use the user selects the
target folder via the picker. The app stores a **security-scoped bookmark** to that
folder, allowing it to reconnect automatically in future sessions when that drive is
plugged in — without prompting the user again. The user can manage multiple known
targets (add, remove, rename) from a settings screen.

This means the typical session flow for the primary use case is:
plug in card → plug in drive → open app → tap Go.

For drive-to-drive backup: plug in both drives → open app → select source folder →
confirm target → tap Go. The target bookmark means the destination drive is already
known; only the source needs selection.

---

## §4 — Module Breakdown

*(Modules will be defined and detailed here as they are discussed and agreed upon.)*

| # | Module | Status |
|---|--------|--------|
| 1 | Source & Destination Selection | ✅ Built |
| 2 | Source Scanning & Incremental Comparison | ✅ Built |
| 3 | Copy Engine | ✅ Built |
| 4 | Verification | ✅ Built |
| 5 | Progress & Status UI | ✅ Built |
| 6 | Results & History | ✅ Built |
| 7 | File Browser | ✅ Built |

---

## §5 — Verification Approach

**✅ DECIDED: SHA-256 checksums.**

Process:
1. Read the source file and compute its SHA-256 hash.
2. Copy the file to the destination.
3. Read the destination file and compute its SHA-256 hash.
4. Compare the two hashes. Match = verified good copy. Mismatch = copy failed.

**Rationale (agreed with Scott, 2026-04-21):**
- SHA-256 is the gold standard — a matching hash is cryptographic proof the bytes arrived intact.
- The performance cost of hashing is irrelevant in practice: the bottleneck is always the USB
  read speed of the camera card. Any iOS/iPadOS device computes SHA-256 faster than the card
  can feed it data.
- SHA-256 produces a reusable fingerprint. The checksum log can be saved and used to re-verify
  the files at any point in the future without the original source.
- This is what professional backup tools (e.g. Hedge, ShotPut Pro) use for exactly these reasons.

---

## §5d — Card Identity, Folder Structure & Incremental Sync

**✅ DECIDED. Inspired by Little Backup Box (Linux), adapted for iOS/iPadOS.**

### Card Identity: Volume UUID

Every card is identified by its **filesystem UUID** — a unique identifier written to the
card by the camera at format time. On iOS this is read via `URLResourceKey.volumeUUIDStringKey`,
a standard Apple API. No jailbreak, no private framework access needed.

When a card is reformatted (in-camera), the camera writes a new UUID. From the app's
perspective, this is a new card with a fresh identity — even if it's the same physical card.

The UUID is used internally (as the database key) only. It is never shown to the user
and never appears in any folder name on disk.

### Card Detection

A volume is treated as a camera card if it contains a `DCIM` folder at its root.
This is the universal DCIM standard used by all digital cameras.

### Camera Name Extraction (verified from sample card)

The camera make/model string ("Canon EOS R6 Mark III") is embedded in the first 64KB
of both CR3 (RAW) and MP4 files. On iOS this is read cleanly via `ImageIO` (for stills)
and `AVFoundation` (for video) — both standard Apple frameworks, no third-party tools.

The app should try stills first (any `.CR3` or `.JPG` in `DCIM/`), then video
(any `.MP4` in `XFVC/`) as fallback. If neither yields a camera name (e.g. a card with
only settings files and no media yet), the naming dialog leaves the camera field blank
for the user to fill in manually.

### First Insertion: Friendly Name Prompt

The first time a card with an unknown UUID is inserted, the app presents a **naming dialog**
before doing anything else. The dialog:

1. Reads camera make/model from any media file on the card (see Camera Name Extraction above).
2. Counts how many cards from this camera are already known → suggests "Card-N+1".
3. Pre-fills the name field with the suggestion (e.g. `EOS R6 Mark III Card-2`).
4. The user can accept or edit the name before proceeding.
5. The confirmed camera model is stored in the database as a named field on the card record
   (not just inferred at runtime) — this is required for the settings restore stretch goal.

The app then creates the destination folder using the format:

```
YYYYMMDD_[friendly name]/
```

For example: `20260421_EOS R6 Mark III Card-2/`

The datestamp is the date of **first backup**, prepended automatically. This gives folders
a natural chronological sort order in Finder and Files with no user effort.

### Canon EOS R6 Mark III Card Structure (verified from sample card)

```
[Card Root]/
├── CDEFAULT.CSD          ← camera settings: default
├── CSETMAIN.CSD          ← camera settings: main
├── C_FOCUSS.CSD          ← camera settings: focus
├── DCIM/
│   ├── 100EOSR6/         ← RAW stills (.CR3)
│   └── CANONMSC/
│       └── M3100.CTG     ← Canon catalog (internal bookkeeping)
├── XFVC/                 ← ALL video (standard and open gate coexist here)
│   ├── REEL_0003/
│   │   ├── *.MP4         ← standard video
│   │   └── *.MP4         ← open gate video (larger files, same folder)
│   └── CANONMSC/
│       └── M10003.CTG
├── MISC/                 ← Canon placeholder, usually empty
└── CRM/                  ← Camera Remote / wireless, usually empty
    └── CANONMSC/
```

Key observations:
- `.CSD` settings files live at the **card root**, not inside any subfolder
- Standard video and open gate video coexist in `XFVC/REEL_XXXX/` — Canon does NOT
  use separate top-level folders for the two video types
- `MISC/` and `CRM/` are typically empty but must be preserved in the mirror
- Canon catalog files (`.CTG`) in `CANONMSC/` subfolders are internal bookkeeping —
  back them up as part of the mirror, but do not interpret them

### Destination Folder Structure

```
[Destination Root]/
└── 20260421_EOS R6 Mark III Card-2/
    ├── CDEFAULT.CSD
    ├── CSETMAIN.CSD
    ├── C_FOCUSS.CSD
    ├── DCIM/
    │   ├── 100EOSR6/
    │   └── CANONMSC/
    ├── XFVC/
    │   ├── REEL_0003/
    │   └── CANONMSC/
    ├── MISC/
    └── CRM/
```

The entire card structure — including root-level files — is mirrored exactly inside the
named folder. The app does not rename, flatten, or reorganise anything.

### The Reformat-as-Archive Model

When a card is reformatted in-camera:
- The old UUID folder at the destination is untouched. It becomes an implicit archive —
  a complete verified record of everything that was ever on that card.
- The reformatted card presents a new UUID. The app creates a new UUID folder and begins
  a fresh incremental sync into it.
- No user action required. No collision possible. The old and new sessions are in
  separate namespaces by design.

### Incremental Sync Logic

Every run against a card is incremental. Before copying any file, the app checks:

1. Does this file already exist at `[destination]/[UUID]/[relative-path]`?
2. Is there a verified SHA-256 hash on record in the database for this path under this UUID?
3. Does the destination file's current hash match that record?

If all three are true → **skip**. Already have a verified copy.
If any are false → **copy and verify**.

Running the app multiple times per day against the same card is always safe and cheap.
The user never has to think about what was already done.

### Camera Settings Files

Camera settings files (e.g. Canon `.DAT` files stored on the card) are treated as
regular files within the mirror. If a settings file has changed since the last backup
(same path, different checksum), the new version **overwrites** the destination copy —
this is a mirror, and the mirror reflects the current state of the card. The previous
checksum is retained in the database for reference.

> **Note:** This is a deliberate simplification enabled by the UUID folder model.
> Because each card generation (pre- and post-reformat) lives in its own UUID folder,
> there is no risk of confusing settings files from different card lifetimes.

---

## §5c — Error Handling & Recovery Policy

**✅ DECIDED.**

### Per-File Failure: Retry Then Skip

When a file fails to copy or fails verification:
1. Retry the file automatically, up to **3 attempts**, with a brief pause between tries.
2. If all 3 attempts fail, skip the file and continue with the remaining files.
3. Present a **prominent warning dialog** immediately naming the specific file and the
   error reason (e.g. "Could not read GOPR0042.MP4 — source read error after 3 attempts").
   The user must dismiss this dialog before the session continues. It cannot be missed.
4. The skipped file is recorded in the session log as failed, with the error reason.
5. The session ends with a summary that makes failures impossible to overlook.

### Partial File Cleanup

If a copy is interrupted mid-file (read error, card removed, destination full, app killed),
the partially-written destination file is **deleted immediately**. A partial file at the
destination is worse than no file — it could be mistaken for a complete copy.

### Card Removed Mid-Session ("Sync Again" Model)

If the source card is removed during a session, the session stops. On reconnect and re-run,
the app behaves like a sync, not a fresh copy:

- Files already **successfully copied and verified** (SHA-256 hash on record matches the
  destination file's current hash) are **skipped**. No redundant work.
- Files that failed or were not yet reached are attempted normally.
- Any partial file left from the interrupted session is cleaned up before the new run begins.

This means re-running against the same source→destination pair is always safe. The user
does not need to think about what was already done.

---

## §5b — Session History & Checksum Database

**✅ DECIDED: Internal SwiftData database. No files written to the user's folders.**

### What Gets Stored

Each copy session produces one `CopySession` record containing:
- Date and time of the session
- Source path (e.g. the camera card volume)
- Destination path (e.g. the external SSD)
- Per-file records: filename, file size, SHA-256 hash, copy result (pass/fail), timestamp

This data lives entirely inside the app's own sandboxed storage. The user's destination
folder remains untouched — no `.sha256` files, no hidden metadata, nothing unexpected.

### Why SwiftData

SwiftData is Apple's persistence framework introduced in iOS 17 — our minimum target.
It is designed to work naturally with SwiftUI, requires minimal boilerplate, and uses
SQLite under the hood without exposing it. Using SwiftData is the correct "work with
Apple" choice here. No third-party database library is needed or wanted.

### Purge Triggers

History records can be removed in two ways:

1. **User-initiated:** A history/log screen lets the user manually delete individual
   sessions or clear all history. This is the primary mechanism.

2. **Opportunistic cleanup:** When the user opens the history view (or on app launch),
   the app checks whether the destination path for each stored session is still accessible.
   If a volume is gone (card ejected, drive reformatted, drive renamed), the app flags
   those sessions as "destination unavailable" and offers to remove them. It does not
   delete them silently — the user confirms.

The app does not run background scans or use file-system watchers. Checks happen only
at natural moments (launch, opening history) to keep the implementation simple.

### Scope Note

Forensic use cases (proving a file hasn't been altered since copy, chain-of-custody logs)
are explicitly out of scope. The database is a practical convenience tool — useful for
re-verifying a destination drive or reviewing what was copied in a past session — not an
evidentiary record.

---

## §6 — Coding Rules

*(Full rules live here. The Four Rules are summarised in both CLAUDE.md files.)*

### §6.1 — Simplest Solution That Works
Use Apple's SDK wherever it provides what's needed. Prefer clarity over cleverness.
When two approaches work, the simpler one wins.

### §6.2 — Comments Are Part of the Deliverable
Every file: header comment. Every function: plain-English explanation.
When iteration was required to reach a working solution, the final comment records the journey —
what was tried, what failed, why the working approach works. Stale comments are deleted.

### §6.3 — One File, One Job
No file over ~200 lines. Views are UI only. Models are data only.
ViewModels and services hold business logic. Split before expanding.

### §6.4 — No Magic Numbers
Any value that could change (chunk size, timeout, retry count, UI dimension) is a named constant
defined at the top of the file or in a dedicated Constants file. Never inline unexplained numbers.

### §6.5 — Work With Apple, Not Against It
If an approach requires fighting SwiftUI or UIKit — flag it before writing code.
Use the phrase: *"This approach requires fighting the framework."*
Describe the problem, propose an alternative, and let Scott decide.

---

## §7 — Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | Verification method (checksum vs byte comparison vs size+date) | ✅ SHA-256 checksums |
| 2 | Should the app save a checksum log file alongside the copied files? | ✅ Internal database (SwiftData), not a file |
| 3 | What happens if a copy fails mid-transfer — retry, skip, or abort? | ✅ Retry then skip; partial files cleaned up; re-run skips already-verified files |
| 4 | Should the app support renaming files during copy (e.g. date-based folders)? | ✅ No reorganisation. Folder structure preserved exactly. Filename collisions resolved via EXIF timestamp append. |

---

## §8 — Decisions Made

*(Logged here as they are agreed, so future sessions don't re-open settled questions.)*

| Date | Decision |
|------|----------|
| 2026-04-21 | Project created. Planning workspace established. |
| 2026-04-21 | Verification method: SHA-256 checksums. Rationale: correctness is the priority; hashing speed is not a constraint because USB card read speed is always the bottleneck. |
| 2026-04-21 | Checksum log: stored in an internal SwiftData database, not as files in the user's folders. Purged by user action or opportunistic cleanup when destination paths are no longer accessible. Forensic use cases explicitly out of scope. |
| 2026-04-21 | Copy failure policy: retry the failed file (3 attempts), then skip with a prominent warning dialog naming the specific file and the error. Any partially-written destination file is deleted immediately on failure. A re-run of the same source→destination is idempotent: files already copied and verified (hash on record matches destination) are skipped. |
| 2026-04-21 | Card identity model: each card is identified by its filesystem UUID (read via URLResourceKey.volumeUUIDStringKey). UUID is internal only — never shown to user, never used as folder name. At destination, each card gets a folder named YYYYMMDD_[friendly name]. On first insertion, the app reads EXIF camera make/model, suggests "EOS R6 Mark III Card-N", user can accept or edit. Reformatting a card produces a new UUID → new folder → old folder becomes a permanent archive automatically. |
| 2026-04-21 | Source and target are symmetric — any accessible folder can be either. Storage medium (card, internal storage, external drive) is irrelevant to the copy engine. One source at a time. Source is always selected fresh via system picker (transient). Target is persisted via security-scoped bookmark (reconnects automatically). Camera-card enhancements (UUID, EXIF naming, dated folder) activate only when a card volume is detected. |
| 2026-04-21 | iCloud Drive is a fully supported target. Treated as any other folder by the copy engine. iCloud's eviction of local copies is expected and desirable — the database checksum record is sufficient proof of verified backup. |
| 2026-04-21 | Available space: use volumeAvailableCapacityForImportantUsageKey as a soft warning only (warn under 2 GB, constant named minimumWarningSpaceBytes). Never block a session. Actual disk-full errors handled by retry-then-skip policy. |
| 2026-04-21 | Post-backup source cleanup: after a 100% successful session where source was VBB Internal Storage, offer to delete source files from the device. Explicit user confirmation required. Never automatic. Logged in session history. Implemented in Module 6. |
| 2026-04-22 | All 7 modules built and tested on device. Core backup flow working: card → VBB Internal Storage, card → iCloud Drive, internal → external confirmed. |
| 2026-04-22 | Incremental scan fix: match FileRecords by destination path prefix (stable) instead of source root path (changes on each USB mount). Also added filesystem-level skip check — if destination file exists with matching size, skip even without a DB record. |
| 2026-04-22 | Verify-only mode: when destination file exists with matching size but no DB record, hash the destination and create a FileRecord without copying. Self-heals the database after reinstall or history clear. |
| 2026-04-22 | Source picker: security-scoped bookmark saved to UserDefaults after each pick. On next present, picker opens at the bookmarked location. Fallback: non-resolving URL forces Browse/Locations view instead of iOS "last used" default. |
| 2026-04-22 | VBB Internal Storage: app creates Documents/VBB Internal Storage folder as a built-in target. UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace set so it appears in Files app. Internal archives shown as one-tap source options on the main screen. |
| 2026-04-22 | Debug logging: file-based logger (DebugLogService) writes to user-selected iCloud Drive folder. Needed because USB port is occupied by card reader during testing. Configurable in Settings. |
| 2026-04-22 | Terminology: all "iPad" references in code and UI replaced with "local storage." Cleanup offer trigger tightened to only fire when source is specifically VBB Internal Storage (not iCloud Drive or other "internal" volumes). |

---

## §9 — Stretch Goals

Features that are explicitly deferred from v1 but should be designed around — meaning the
v1 architecture should not make them hard to add later. Do not build these until the core
app is complete and stable.

### §9.1 — Camera Settings Restore to Card

**What it does:** When a newly formatted (empty) card is connected, offer to restore the
most recently backed-up camera settings files for the associated camera onto the card.
Canon's EOS R6 Mark III (and similar cameras) can write and read back settings files
stored on the card — but these are lost on format. This feature recovers them from the
backup without any manual hunting.

**Why it's deferred:** It requires reverse-copy logic (backup store → card), camera
association in the database, and careful UX. The core copy engine goes source → target
only. This adds a new direction and should not be attempted until the core is solid.

**Design constraints to observe now (so v1 doesn't block this later):**

1. **Camera association must be explicit in the database.** When a card is named, the
   camera make/model must be stored as a field in the card record — not just inferred
   from EXIF at runtime. This is the key that lets the app later ask "what settings
   backups exist for this camera?"

2. **Settings files must be tagged in the database.** The copy engine needs to mark
   certain file types as "camera settings" so they can be queried separately from media
   files. For the Canon EOS R6 Mark III (verified from sample card): settings files use
   the `.CSD` extension and live at the **card root level** — not inside any subfolder.
   Detection rule: `*.CSD` at root. Other camera brands will need their own patterns
   added to a lookup table when known. Do not hardcode Canon-only logic into the engine.

3. **The naming dialog is the right place to establish camera association.** On first
   insertion of a new (or reformatted) card, the naming dialog already asks for a
   friendly name and suggests a camera model. That camera model selection should be
   stored — not discarded after naming.

4. **Trigger points to support:** (a) automatically, when a new UUID card with no media
   files is detected — offer restore before doing anything else; (b) manually, at any
   time from the card detail or history screen. The user should never be forced into a
   restore — it is always an offer, not an action.

5. **The restore is a copy operation, not a database sync.** Files are written from the
   backed-up location to the card. The database is updated to record the restore event
   but the card's new UUID folder is not pre-populated with restored-file records as if
   they were "already backed up" — they need to be re-verified the next time the card
   is synced.

---

## §10 — Module Directives

Each module has its own spec file in `Docs/`. Read the relevant file before building
that module. Do not build a module before the one it depends on is complete.

**Data layer reference (read before any module):** `00_DATA_MODELS.md`

| Module | File | Status |
|--------|------|--------|
| 1 — Source & Target Selection | `01_MODULE_SOURCE_TARGET_SELECTION.md` | ✅ Scoped |
| 2 — Source Scanning & Incremental Comparison | `02_MODULE_SOURCE_SCANNING.md` | ✅ Scoped |
| 3 — Copy Engine | `03_MODULE_COPY_ENGINE.md` | ✅ Scoped |
| 4 — Verification | `04_MODULE_VERIFICATION.md` | ✅ Scoped |
| 5 — Progress & Status UI | `05_MODULE_PROGRESS_UI.md` | ✅ Scoped |
| 6 — Results & History | `06_MODULE_RESULTS_HISTORY.md` | ✅ Scoped |
| 7 — File Browser | `07_MODULE_FILE_BROWSER.md` | ✅ Scoped |

---
*End of directive. If you've read this far, you're ready to work.*
