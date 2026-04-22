# Module 3 — Copy Engine

**Status:** Scoped, ready to build
**Depends on:** Module 1 complete, Module 2 complete, all SwiftData models created
**Blocks:** Module 4 (Verification), Module 5 (Progress UI)
**Last Updated:** 2026-04-21

> Before building this module, read `00_OVERALL_DIRECTIVE.md` and `00_DATA_MODELS.md`
> in full. This document covers Module 3 only. Module 4 (Verification) is tightly
> coupled to this module — read Module 4's spec before finalising any interfaces here.

---

## What This Module Does

Module 3 takes the `ScanResult` from Module 2 — the list of files that need to be
copied — and physically moves bytes from source to destination.

It also creates and maintains the `CopySession` database record for the session.

For each file it copies, it hands a source hash and destination URL to Module 4
(Verification). Module 3 does not verify anything itself — verification is Module 4's
job. But Module 3 and Module 4 are tightly coupled in execution: they run alternately
per file, not in two separate passes over all files.

**The per-file sequence is:**
```
Module 3: compute source hash + stream to destination
     ↓
Module 4: hash destination + compare + write FileRecord or record failure
     ↓
Module 3: move to next file (or retry on failure)
```

---

## Key Design Decision: Hash While Copying

The source file SHA-256 hash is computed **on the fly during the copy stream** — not
as a separate pre-copy read pass.

This is the right approach because:
- Large video files (300–400 MB) would otherwise require two full source reads.
- A single streaming pass reads the source once, feeds chunks simultaneously to the
  SHA-256 hasher and the destination write stream.
- This is how professional backup tools (Hedge, ShotPut Pro) work.
- At the end of the stream, the source hash is finalised and ready for Module 4.

The implementation uses `CryptoKit.SHA256` (Apple's framework, iOS 13+) for incremental
hashing — `SHA256.Hasher` accepts chunks via `update(data:)` and produces the final
digest via `finalize()`.

---

## The Copy Stream

Manual streaming is required (not `FileManager.copyItem`) because:
1. `FileManager.copyItem` is opaque — no progress reporting during copy.
2. We need to feed chunks to the SHA-256 hasher simultaneously.
3. We need cancellation checkpoints between chunks.

**Implementation:**

```swift
// Pseudocode — actual implementation in CopyEngine.swift
func copyFile(from source: URL, to destination: URL) async throws -> String {
    // Returns the source SHA-256 hex string on success.
    // Throws on any read, write, or cancellation error.

    var hasher = SHA256()
    let inputStream = InputStream(url: source)
    let outputStream = OutputStream(url: destination, append: false)

    // Open streams, read chunks, update hasher, write chunks.
    // Check Task.isCancelled between chunks.
    // On any error: close streams, delete partial destination file, throw.

    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
}
```

**Chunk size:** Defined as `copyChunkSizeBytes` in `Constants.swift`. Default: 4 MB
(4 * 1024 * 1024 bytes). This balances memory use against system call overhead.
Large enough to be efficient; small enough for responsive cancellation and progress.

---

## Destination Directory Creation

Before writing any file, the destination directory must exist. The copy engine creates
it if needed:

```swift
try FileManager.default.createDirectory(
    at: destinationURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
```

`withIntermediateDirectories: true` means the full path is created in one call,
regardless of how many nested folders are needed. This handles the Canon DCIM hierarchy
(`DCIM/100EOSR6/`) and root-level files (`.CSD` files, which need no subdirectory)
correctly without any special cases.

---

## Partial File Cleanup

If a copy fails at any point — read error, write error, disk full, cancellation — the
partial destination file must be deleted before throwing. A partial file at the
destination is worse than no file.

Use `defer` to guarantee cleanup on all exit paths:

```swift
var destinationCreated = false
defer {
    if destinationCreated && copyFailed {
        try? FileManager.default.removeItem(at: destinationURL)
    }
}
```

The `try?` on removeItem is intentional — if cleanup itself fails, we still need to
propagate the original error, not a cleanup error. Log the cleanup failure but do not
let it mask the root cause.

---

## Retry Logic

Retry is managed by `BackupSessionService` (the orchestrator), not by `CopyEngine`.
`CopyEngine` either succeeds or throws — it has no retry logic itself. This keeps
the engine simple and testable.

`BackupSessionService` catches a thrown error and retries the file up to
`maxCopyRetries` times (defined in `Constants.swift`, default: 3). Between retries
it waits `retryDelaySeconds` (default: 2.0 seconds) to give transient errors
(e.g. a brief USB hiccup) time to clear.

After all retries are exhausted:
1. The failure is recorded on the `CopySession` (`filesFailed += 1`).
2. The failed file name and error reason are posted to the UI (Module 5).
3. The session continues with the next file.

The retry count and delay are named constants — never magic numbers.

---

## The Session Orchestrator: BackupSessionService

`BackupSessionService` is the coordinator that spans Modules 3 and 4. It lives in
`Services/BackupSessionService.swift` and is responsible for:

1. Creating the `CopySession` database record at session start.
2. Iterating `ScanResult.filesToCopy`.
3. Calling `CopyEngine.copyFile()` per file.
4. Passing the result to `VerificationEngine.verify()` (Module 4).
5. Managing retries on failure.
6. Posting progress updates to `SessionViewModel`.
7. Updating `CopySession` counters (`filesCopied`, `filesFailed`, `filesSkipped`).
8. Updating `KnownCard.lastBackupDate` on session completion.
9. Marking the `CopySession` with its final `SessionStatus` on completion.
10. Handling cancellation: if the user cancels, finish the current file cleanly,
    then stop. Mark the session as `.interrupted`.

`BackupSessionService` is the only place in the codebase that calls both
`CopyEngine` and `VerificationEngine`. No View or ViewModel calls them directly.

---

## Cancellation

The user can cancel a session at any time during copy. Cancellation is cooperative:

- `BackupSessionService` checks `Task.isCancelled` between files.
- `CopyEngine` checks `Task.isCancelled` between chunks during streaming.
- On cancellation: complete the current chunk write, close streams cleanly,
  delete the partial destination file, then stop.
- The session is marked `.interrupted` in the database.
- Files already verified in this session retain their `FileRecord` entries —
  the next run will correctly skip them.

---

## Files To Build

```
VirtualBackupBox/
├── Services/
│   ├── CopyEngine.swift            ← streams one file source→destination,
│   │                                  computes source SHA-256 on the fly,
│   │                                  handles partial file cleanup on failure
│   └── BackupSessionService.swift  ← session orchestrator: iterates file list,
│                                      manages retries, coordinates CopyEngine
│                                      and VerificationEngine, updates database
├── ViewModels/
│   └── SessionViewModel.swift      ← exposes live session state to the UI:
│                                      current file, bytes progress, file counts,
│                                      failure list. No business logic here.
└── Constants.swift                 ← (create if not already present)
                                       copyChunkSizeBytes: Int = 4 * 1024 * 1024
                                       maxCopyRetries: Int = 3
                                       retryDelaySeconds: Double = 2.0
                                       minimumWarningSpaceBytes: Int64 = 2 * 1024 * 1024 * 1024
```

Note: `Constants.swift` consolidates all named constants for the whole app.
If it already exists from a prior module, add to it — do not create a second file.

---

## Progress Reporting

`CopyEngine` reports progress to `BackupSessionService` via a closure or
`AsyncStream`. `BackupSessionService` aggregates and forwards to `SessionViewModel`.

Progress has two levels:

**Byte-level** (updated every chunk, ~4 MB intervals):
- `currentFileName: String`
- `currentFileBytesWritten: Int64`
- `currentFileTotalBytes: Int64`

**File-level** (updated after each file completes):
- `filesCompleted: Int`
- `filesFailed: Int`
- `totalFiles: Int`
- `totalBytesWritten: Int64`
- `totalBytesToWrite: Int64`

`SessionViewModel` exposes both levels as `@Published` properties. Module 5
(Progress UI) binds to these. Module 3 must not contain any UI code.

---

## What Module 3 Does NOT Do

- Does not verify. Verification is Module 4.
- Does not write `FileRecord` entries. Module 4 writes them.
- Does not read or write any source file content beyond streaming it to destination.
  Source is always read-only (§2 of overall directive).
- Does not make any UI decisions. It posts data; Module 5 displays it.
- Does not handle the "already backed up" files from the ScanResult. Those were
  handled in Module 2. Module 3 only receives files tagged for copy.

---

## Key Constraints & Cautions

**CryptoKit is available on iOS 13+ and requires no import beyond `import CryptoKit`.**
Use `SHA256.Hasher` for incremental hashing. Do not use CommonCrypto or any
third-party hashing library.

**InputStream/OutputStream require manual open/close calls.** Always close in a
`defer` block. Forgetting to close is a file handle leak.

**iCloud Drive targets behave like local folders for write purposes.** `OutputStream`
and `FileManager.createDirectory` work on iCloud Drive URLs returned by the document
picker without any special handling. Do not add iCloud-specific code paths.

**Do not use `FileManager.copyItem` as a shortcut.** It provides no progress, no
hash, and no cancellation. The streaming implementation is required.

**Large files will take time.** A 384 MB open-gate video file over a USB card reader
at 90 MB/s takes roughly 4 seconds just to read. The progress stream must update
frequently enough that the user sees movement. One update per chunk (every 4 MB)
is sufficient.

**Security-scoped resource access must be active during copy.** Both source and
destination URLs must have `startAccessingSecurityScopedResource()` called before
any stream is opened. This is managed by `BackupSessionService`, which coordinates
with `BookmarkService` (Module 1). `CopyEngine` receives pre-authorised URLs and
does not manage security scope itself.

---

## Open Questions for This Module

| # | Question | Status |
|---|----------|--------|
| 1 | Should the user be able to pause (not just cancel) a session? | ❓ Defer to v2. Cancel only for v1. |
| 2 | Should failed files be retried at the end of the session rather than inline? | ❓ Inline retry is simpler and matches expected UX. Keep inline for v1. |

---

## Definition of Done

Module 3 is complete when:
- [ ] `CopyEngine` streams a file from source to destination in chunks, computing
      SHA-256 on the fly. Returns the source hash string on success.
- [ ] Chunk size is a named constant. No magic numbers anywhere.
- [ ] Partial destination file is deleted on any failure (read, write, cancel).
      Verified with a test that interrupts a copy mid-stream.
- [ ] `BackupSessionService` iterates the file list, calls copy + verify per file,
      retries up to 3 times on failure, then skips with failure recorded.
- [ ] `CopySession` is created at session start and updated throughout.
      `SessionStatus` is set correctly on completion, partial completion, and interrupt.
- [ ] Cancellation stops the session cleanly after the current file. Already-verified
      files are not re-copied on the next run (their FileRecords are intact).
- [ ] `SessionViewModel` exposes byte-level and file-level progress as `@Published`
      properties. Values update correctly during a live session.
- [ ] Tested against the Sample Camera Card: all files copy correctly to a test
      destination folder, with correct directory structure preserved.
- [ ] No file exceeds ~200 lines. No UI logic in services. No business logic in views.
