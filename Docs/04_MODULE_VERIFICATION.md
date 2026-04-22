# Module 4 — Verification

**Status:** Scoped, ready to build
**Depends on:** Module 3 (Copy Engine) — specifically `CopyEngine` and `BackupSessionService`
**Blocks:** Module 5 (Progress & Status UI), Module 6 (Results & History)
**Last Updated:** 2026-04-21

> Before building this module, read `00_OVERALL_DIRECTIVE.md`, `00_DATA_MODELS.md`,
> and `03_MODULE_COPY_ENGINE.md` in full. Module 4 is tightly coupled to Module 3 —
> they are built and tested together.

---

## What This Module Does

Module 4 answers one question per file: **"Did the bytes that arrived at the destination
exactly match the bytes that left the source?"**

It receives the source SHA-256 hash (computed by Module 3 during the copy stream) and
the destination URL. It reads the destination file, computes its SHA-256 hash, and
compares. On a match it writes a `FileRecord` to the database. On a mismatch it deletes
the destination file and returns a failure to `BackupSessionService`.

Module 4 is the only place in the codebase that writes `FileRecord` entries.

---

## What Module 4 Does NOT Do

- Does not copy files. That is Module 3.
- Does not compute the source hash. Module 3 computes it during the copy stream.
- Does not retry. Retry logic lives in `BackupSessionService` (Module 3).
- Does not display anything. Progress is posted to `SessionViewModel`; Module 5 displays it.
- Does not read the source file. The source is read once by Module 3. Module 4 reads
  the destination only. This is deliberate — the source is read-only (§2 of overall
  directive) and we do not read it a second time.

---

## The Verification Process Per File

```
Input:  sourceHash (String)      — SHA-256 hex string from Module 3
        destinationURL (URL)     — where the file was written
        sourceFile (SourceFile)  — metadata from Module 2 scan result

Step 1: Open destination file for reading.
        If file doesn't exist → return .failure(.destinationNotFound). This indicates
        the copy silently failed to create the file — should not happen, but handle it.

Step 2: Read destination file in chunks (same chunk size as copy: copyChunkSizeBytes).
        Feed each chunk to a SHA256.Hasher.
        Report byte-level progress to SessionViewModel (verification phase).

Step 3: Finalize destination hash → hex string.

Step 4: Compare sourceHash == destinationHash.
        Match   → proceed to Step 5.
        Mismatch → delete destination file, return .failure(.hashMismatch).

Step 5: Create FileRecord and save to SwiftData context.
        Return .success(fileRecord).
```

---

## VerificationResult

```swift
// The outcome returned to BackupSessionService after verifying one file.
enum VerificationResult {
    case success(FileRecord)
    case failure(VerificationError)
}

enum VerificationError: Error {
    // Destination file hash did not match source hash.
    // Both hashes are included so the failure can be logged with detail.
    case hashMismatch(sourceHash: String, destinationHash: String)

    // Could not read the destination file.
    case destinationReadError(underlying: Error)

    // Destination file does not exist. Copy engine should have created it.
    case destinationNotFound
}
```

`BackupSessionService` receives this result and decides whether to retry (on failure)
or move to the next file (on success).

---

## On Mismatch: Delete the Destination File

A hash mismatch means the destination file is corrupt — the bytes that arrived do not
match the bytes that left. A corrupted file at the destination is worse than no file
(it could be mistaken for a good copy on a future run).

On any `VerificationError`, the destination file is deleted before returning:

```swift
try? FileManager.default.removeItem(at: destinationURL)
```

The `try?` is intentional — if the delete fails, we still need to return the
verification error, not a delete error. Log the delete failure separately.

After deletion, `BackupSessionService` decides whether to retry the copy. If all
retries fail, the file is recorded as failed and the session continues.

---

## FileRecord Creation

On a successful verification, `VerificationEngine` creates and saves the `FileRecord`:

```swift
let record = FileRecord(
    relativeSourcePath: sourceFile.relativePath,
    absoluteSourceRoot: sourceFile.sourceRoot.path,
    absoluteDestinationPath: destinationURL.path,
    sha256Hash: sourceHash,          // the verified hash (matches both source and destination)
    fileSizeBytes: sourceFile.fileSizeBytes,
    isSettingsFile: sourceFile.isSettingsFile
)
record.session = currentSession      // link to the active CopySession
context.insert(record)
// SwiftData autosaves — no explicit save() call needed in most configurations.
// If using manual save, call try context.save() here.
```

The hash stored in `FileRecord` is the **source hash** (computed by Module 3). Since
verification has confirmed it matches the destination hash, either value would be
correct — but we store the source hash because that's what Module 2 would compare
against on a future scan if the destination file were somehow re-hashed.

---

## Progress Reporting: Two Phases Per File

From the user's perspective, each file goes through two visible phases:
1. **Copying** — bytes streaming from source to destination (reported by Module 3)
2. **Verifying** — destination being read and hashed (reported by Module 4)

`SessionViewModel` exposes a `currentPhase` property:

```swift
enum SessionPhase {
    case copying(fileName: String, bytesWritten: Int64, totalBytes: Int64)
    case verifying(fileName: String, bytesRead: Int64, totalBytes: Int64)
    case idle
}
```

`VerificationEngine` updates `SessionViewModel.currentPhase` to `.verifying` at the
start of each file and posts byte-level progress as it reads. Module 5 binds to this
and displays the appropriate UI for each phase.

---

## Future Use: Deep Verify

`VerificationEngine` is deliberately designed to accept any `(sourceHash, destinationURL)`
pair — it has no knowledge of whether this is an initial copy or a re-check.

This makes it directly reusable for a future "Deep Verify" feature: re-reading all
destination files and comparing their current hashes against the stored `FileRecord`
hashes, to confirm nothing has changed on the destination drive since backup.

For Deep Verify, the call would be:
```swift
// Source hash comes from the stored FileRecord, not from a live copy.
verificationEngine.verify(
    sourceHash: fileRecord.sha256Hash,
    destinationURL: URL(fileURLWithPath: fileRecord.absoluteDestinationPath),
    ...
)
```

Do not build Deep Verify now. Do not add Deep Verify parameters or branches to this
module. Just keep the interface clean so it's possible later without a rewrite.

---

## Files To Build

```
VirtualBackupBox/
└── Services/
    └── VerificationEngine.swift    ← hashes destination file in chunks,
                                       compares to source hash, writes FileRecord
                                       on success, deletes destination on failure,
                                       reports verification progress to SessionViewModel
```

No new ViewModel or View files in this module. `SessionViewModel` (Module 3) gains
a `currentPhase` property and a `verificationProgress` value — add these to the
existing file, do not create a new ViewModel.

`VerificationEngine` should be under ~150 lines. If it grows beyond that, the chunk-
reading logic should be extracted into a shared `SHA256FileHasher` utility that both
`CopyEngine` and `VerificationEngine` use. Do not duplicate the streaming hash logic.

---

## Shared Hashing Utility (If Needed)

If `CopyEngine` and `VerificationEngine` end up with duplicated chunk-reading and
hashing code, extract it:

```
VirtualBackupBox/
└── Services/
    └── SHA256FileHasher.swift  ← reads a file in chunks, feeds to SHA256.Hasher,
                                   returns hex string. Used by both engines.
                                   Accepts a progress closure for reporting.
```

`CopyEngine` would use `SHA256FileHasher` to hash the source during the copy stream.
`VerificationEngine` would use it to hash the destination.

Extract this only if the duplication is real — do not pre-optimise. Build both engines
first; refactor if duplication becomes obvious.

---

## Key Constraints & Cautions

**Module 4 reads the destination, not the source.** The source has already been read
by Module 3 and must not be read again. If there is ever a temptation to re-read the
source in this module, stop and flag it — something has gone wrong in the design.

**The FileRecord hash field stores the source hash, not the destination hash.** They
are equal after a successful verification — but always store the source hash. This is
consistent with what Module 2 would compute if performing a Deep Verify later.

**SwiftData context must be the same context used throughout the session.** Do not
create a new `ModelContext` in `VerificationEngine`. Receive the context as a parameter
from `BackupSessionService`. Creating multiple contexts for the same data risks
conflicting writes.

**Verification progress updates must be posted on the main actor.** `SessionViewModel`
is `@MainActor`. Use `await MainActor.run { }` or `@MainActor` annotations when
updating it from the background task running `VerificationEngine`.

**Do not call `context.save()` after every FileRecord if using autosave.** SwiftData's
default configuration autosaves on the run loop. Calling save() after every file in a
large session creates unnecessary overhead. If manual save is needed for reliability,
batch saves (e.g. every 10 files or at session end) are preferable to per-file saves.
Confirm autosave behaviour in testing before deciding.

---

## Open Questions for This Module

| # | Question | Status |
|---|----------|--------|
| 1 | Deep Verify feature (re-hash all destination files on demand) | ❓ Future — architecture accommodates it. Do not build now. |
| 2 | Should verification progress be shown per-byte or just a spinner per file? | ❓ Per-byte preferred for large video files. A spinner is acceptable for files under 10 MB — use `fileSizeBytes` from `SourceFile` to decide which to show. Named constant: `verificationProgressThresholdBytes` in `Constants.swift`. |

---

## Definition of Done

Module 4 is complete when:
- [ ] `VerificationEngine.verify()` reads a destination file in chunks, computes its
      SHA-256 hash, and compares it to the provided source hash.
- [ ] On match: `FileRecord` is created and inserted into SwiftData with all fields
      populated correctly, including `isSettingsFile` and `session` relationship.
- [ ] On mismatch: destination file is deleted, `.failure(.hashMismatch)` is returned.
      Both hashes are included in the error for logging.
- [ ] On missing destination: `.failure(.destinationNotFound)` is returned.
- [ ] `SessionViewModel.currentPhase` updates to `.verifying` during verification,
      with byte-level progress for files above the threshold.
- [ ] Tested end-to-end: copy a file via Module 3, verify via Module 4, confirm
      `FileRecord` is in the database with correct hash and metadata.
- [ ] Tested failure path: modify a destination file after copy, confirm verification
      catches the mismatch, deletes the file, and returns the correct error.
- [ ] `VerificationEngine` is under ~150 lines. Hashing logic is not duplicated
      between `CopyEngine` and `VerificationEngine` (extract `SHA256FileHasher` if needed).
- [ ] No file exceeds ~200 lines. No UI logic in services.
