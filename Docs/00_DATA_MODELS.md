# Virtual Backup Box — SwiftData Models Reference

**Status:** Canonical — all SwiftData models are defined here.
**Last Updated:** 2026-04-21

> This document is the single source of truth for the app's data layer.
> Read this before building any module that reads from or writes to the database.
> If a model needs to change, update this document first, then update the affected
> module specs, then change the code. Never let the code drift from this spec.

---

## Overview

The app uses SwiftData (iOS 17+) for all persistence. There are four models:

| Model | Written by | Read by | Purpose |
|-------|-----------|---------|---------|
| `KnownCard` | Module 1 | Modules 1, 2, 6 | Tracks known camera cards by UUID |
| `KnownTarget` | Module 1 | Module 1 | Tracks known backup destinations |
| `CopySession` | Module 3/4 | Module 6 | One record per backup session |
| `FileRecord` | Module 4 | Modules 2, 6 | One record per successfully verified file |

All models are defined in `Models/` in the Xcode project. Each model gets its own file
(§6.3 — one file, one job).

---

## KnownCard

**File:** `Models/KnownCard.swift`
**Written by:** Module 1 (on first card insertion, after naming dialog)
**Updated by:** Module 3/4 (lastBackupDate after each successful session)
**Read by:** Modules 1, 2, 6

```swift
// KnownCard.swift
//
// Represents one generation of a physical camera card.
// "Generation" means one format cycle — a reformatted card gets a new UUID
// and therefore a new KnownCard record. The old record remains as a permanent
// archive reference. This is intentional and matches the reformat-as-archive model
// described in §5d of the overall directive.

@Model
final class KnownCard {

    // The card's filesystem volume UUID, read via URLResourceKey.volumeUUIDStringKey.
    // This is the primary identifier — it never changes for the life of this card
    // generation. Used to recognise a card on re-insertion without user input.
    var uuid: String

    // User-assigned name, confirmed in the naming dialog on first insertion.
    // Example: "EOS R6 Mark III Card-1"
    var friendlyName: String

    // Camera model string extracted from EXIF/metadata on first insertion and
    // confirmed by the user in the naming dialog.
    // Example: "Canon EOS R6 Mark III"
    // Stored explicitly (not inferred at runtime) because an empty reformatted card
    // has no media files to read EXIF from. Required for the settings restore
    // stretch goal (§9.1).
    var cameraModel: String

    // The folder name created at the target root for this card's mirror.
    // Format: "YYYYMMDD_[friendlyName]" — date is the date of first backup.
    // Example: "20260421_EOS R6 Mark III Card-1"
    // Stored here so it never changes even if the user later renames the card.
    var destinationFolderName: String

    // When this card was first seen by the app.
    var firstSeenDate: Date

    // When the most recent successful backup session for this card completed.
    // Nil if the card has been named but never successfully backed up.
    var lastBackupDate: Date?

    // All backup sessions involving this card as source.
    // Relationship defined in CopySession (inverse: CopySession.sourceCard).
    @Relationship(deleteRule: .cascade, inverse: \CopySession.sourceCard)
    var sessions: [CopySession] = []

    init(uuid: String,
         friendlyName: String,
         cameraModel: String,
         destinationFolderName: String) {
        self.uuid = uuid
        self.friendlyName = friendlyName
        self.cameraModel = cameraModel
        self.destinationFolderName = destinationFolderName
        self.firstSeenDate = Date()
        self.lastBackupDate = nil
    }
}
```

---

## KnownTarget

**File:** `Models/KnownTarget.swift`
**Written by:** Module 1 (when user adds a new target)
**Read by:** Module 1

```swift
// KnownTarget.swift
//
// Represents a known backup destination folder, persisted so the app can
// reconnect to it automatically across sessions without requiring the user
// to re-select it from the document picker.
//
// Persistence works via a security-scoped bookmark (a Data blob that iOS can
// resolve back to a URL even after the app restarts, as long as the volume
// is still accessible). See BookmarkService.swift for how to create and
// resolve these bookmarks.

@Model
final class KnownTarget {

    // User-assigned name for this destination.
    // Example: "Samsung T7", "Vacation Drive", "iCloud Drive"
    var friendlyName: String

    // Security-scoped bookmark data for the target folder URL.
    // Created by BookmarkService when the target is first added.
    // Resolved by BookmarkService at the start of each session.
    // If resolution fails (drive reformatted, renamed, or unavailable),
    // the target is shown as "unavailable" in the UI — never silently removed.
    var bookmarkData: Data

    // When this target was added.
    var addedDate: Date

    // When this target was last used as the destination for a completed session.
    var lastUsedDate: Date?

    // Note: isAvailable is NOT stored — it is computed at runtime by attempting
    // to resolve the bookmark. Storing it would create stale data.

    init(friendlyName: String, bookmarkData: Data) {
        self.friendlyName = friendlyName
        self.bookmarkData = bookmarkData
        self.addedDate = Date()
        self.lastUsedDate = nil
    }
}
```

---

## CopySession

**File:** `Models/CopySession.swift`
**Written by:** Module 3 (created at session start) and Module 4 (updated throughout)
**Read by:** Module 6 (Results & History)

```swift
// CopySession.swift
//
// One record per backup session — from the moment "Start Backup" is tapped
// to the moment the session ends (success, partial, or failure).
//
// A session always has a source path and a target path. If the source is a
// known camera card, sourceCard is populated. If not (generic folder backup),
// sourceCard is nil.

@Model
final class CopySession {

    // When the session started.
    var startDate: Date

    // When the session ended. Nil while the session is in progress.
    var endDate: Date?

    // Absolute path string of the source root folder selected for this session.
    var sourcePath: String

    // Absolute path string of the target root folder for this session.
    var targetPath: String

    // The session folder created at the target root for this session's files.
    // For camera cards: the card's destinationFolderName (e.g. "20260421_EOS R6 Mark III Card-1").
    // For generic folders: the source folder's name.
    var sessionFolderName: String

    // Overall outcome of the session.
    // .inProgress while running, .success, .partialSuccess, or .interrupted when done.
    var status: SessionStatus

    // Whether source files were deleted from local storage after a
    // successful session (Module 6 cleanup offer). Defaults to false.
    var sourceFilesDeleted: Bool

    // The known card this session backed up, if source was a camera card.
    // Nil for generic folder sources.
    var sourceCard: KnownCard?

    // All file-level records for this session.
    // Relationship defined here; FileRecord has inverse FileRecord.session.
    @Relationship(deleteRule: .cascade, inverse: \FileRecord.session)
    var fileRecords: [FileRecord] = []

    // Convenience counts — updated incrementally as files are processed,
    // so the UI can display live progress without querying fileRecords.
    var totalFilesFound: Int       // set at end of Module 2 scan
    var filesCopied: Int = 0       // incremented by Module 4 on each verified file
    var filesSkipped: Int = 0      // incremented by Module 2 for already-backed-up files
    var filesFailed: Int = 0       // incremented by Module 4 on each failure

    init(sourcePath: String,
         targetPath: String,
         sessionFolderName: String,
         sourceCard: KnownCard? = nil,
         totalFilesFound: Int = 0) {
        self.startDate = Date()
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.sessionFolderName = sessionFolderName
        self.sourceCard = sourceCard
        self.totalFilesFound = totalFilesFound
        self.status = .inProgress
    }
}

// The possible outcomes of a CopySession.
enum SessionStatus: String, Codable {
    case inProgress     // session is currently running
    case success        // all files copied and verified; no failures
    case partialSuccess // session completed but one or more files failed
    case interrupted    // session stopped before completion (card removed, user cancelled)
}
```

---

## FileRecord

**File:** `Models/FileRecord.swift`
**Written by:** Module 4 (after each file is verified)
**Read by:** Modules 2 (incremental comparison), 6 (history display)

```swift
// FileRecord.swift
//
// One record per file processed in a CopySession.
//
// This is the core of the incremental backup system. On subsequent runs against
// the same source, Module 2 fetches all FileRecords for the source/target path
// combination and uses them to determine which files already have a verified copy.
//
// A FileRecord is only written after SUCCESSFUL verification (source hash ==
// destination hash). Failed copies do not produce a FileRecord — they produce
// a FailedFileRecord (see below). This means the absence of a FileRecord for
// a given file always means "not yet verified" — there is no ambiguity.

@Model
final class FileRecord {

    // Path of the source file, relative to the session source root.
    // Example: "DCIM/100EOSR6/_MG_1530.CR3"
    // Used by Module 2 for incremental comparison.
    var relativeSourcePath: String

    // Absolute path of the source root at time of copy.
    // Combined with relativeSourcePath to reconstruct the full source URL.
    var absoluteSourceRoot: String

    // Absolute path of the destination file (full path, not relative).
    // Example: "/Volumes/T7/20260421_EOS R6 Mark III Card-1/DCIM/100EOSR6/_MG_1530.CR3"
    var absoluteDestinationPath: String

    // SHA-256 hash of the source file, computed before copy.
    // Also confirmed to match the destination file after copy.
    // Stored as a hex string (64 characters).
    var sha256Hash: String

    // File size in bytes, as reported by the filesystem at time of copy.
    // Used by Module 2 as a quick sanity check before trusting the DB record.
    var fileSizeBytes: Int64

    // When this file was successfully verified.
    var verifiedDate: Date

    // True if this file was identified as a camera settings file
    // (e.g. .CSD for Canon). Used by the settings restore stretch goal (§9.1).
    var isSettingsFile: Bool

    // The session this file was copied in.
    var session: CopySession?

    init(relativeSourcePath: String,
         absoluteSourceRoot: String,
         absoluteDestinationPath: String,
         sha256Hash: String,
         fileSizeBytes: Int64,
         isSettingsFile: Bool = false) {
        self.relativeSourcePath = relativeSourcePath
        self.absoluteSourceRoot = absoluteSourceRoot
        self.absoluteDestinationPath = absoluteDestinationPath
        self.sha256Hash = sha256Hash
        self.fileSizeBytes = fileSizeBytes
        self.verifiedDate = Date()
        self.isSettingsFile = isSettingsFile
    }
}
```

### Why FileRecord Is Only Written on Success

A `FileRecord` represents a guarantee: "this file was copied and the copy was verified."
Writing a record for a failed copy would corrupt the incremental logic — subsequent scans
would skip a file that was never successfully backed up.

Failed files are tracked separately via `CopySession.filesFailed` and the failed-file
warning dialogs (Module 5). They do not produce `FileRecord` entries.

---

## Model Relationships Diagram

```
KnownTarget         KnownCard
    |                   |
    |            (sourceCard, optional)
    |                   |
    +-------→  CopySession  ←-------+
                    |
                    | (one per file)
                    ↓
               FileRecord
```

- `KnownTarget` has no direct relationship to `CopySession` — the target is identified
  by `CopySession.targetPath` (a string), not a SwiftData relationship. This avoids
  complications if a target is renamed or removed while sessions still reference it.
- `KnownCard` → `CopySession` is a one-to-many relationship with cascade delete:
  deleting a card record deletes its session history.
- `CopySession` → `FileRecord` is one-to-many with cascade delete.

---

## Build Order

These models must exist before the modules that use them. Build them in this order:

1. `KnownTarget.swift` — no dependencies
2. `KnownCard.swift` — no dependencies (references CopySession by inverse, defined there)
3. `CopySession.swift` — references KnownCard and FileRecord
4. `FileRecord.swift` — references CopySession

In practice: create all four files before building any module. They compile independently
of module UI and services, and having them in place prevents import errors throughout the build.
