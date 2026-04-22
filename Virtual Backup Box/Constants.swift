// Constants.swift
// Virtual Backup Box
//
// All named constants for the app live in this one file. Any value that could
// change — chunk size, retry count, UI threshold — is defined here rather than
// inlined as a magic number. Adding or adjusting a constant should require
// changing one line in one place.
//
// Constants are grouped by the module that primarily uses them, but any module
// can read any constant. No constant is private.

import Foundation

nonisolated enum Constants {

    // MARK: - Module 1 — Source & Target Selection

    /// Available space threshold for the soft warning on the target drive.
    /// If available space is below this value, the UI shows a visible warning
    /// but does NOT block the session. Actual disk-full errors are handled by
    /// the retry-then-skip policy in the copy engine (§5c).
    /// Value: 2 GB.
    static let minimumWarningSpaceBytes: Int64 = 2 * 1024 * 1024 * 1024

    // MARK: - Module 2 — Source Scanning

    /// Filenames and directory names that are silently excluded from the scan.
    /// These are macOS filesystem artifacts that cameras do not create.
    /// Adding a new exclusion means adding one entry to this array.
    static let excludedFilenames: Set<String> = [
        ".DS_Store",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd"
    ]

    /// Prefix for macOS resource fork files. Any file whose name starts with
    /// this prefix is excluded from the scan. Checked separately from
    /// excludedFilenames because it is a prefix match, not an exact match.
    static let excludedFilePrefix: String = "._"

    // MARK: - Module 3 — Copy Engine

    /// Size of each chunk read from the source file during the copy stream.
    /// Balances memory use against system call overhead. Large enough to be
    /// efficient; small enough for responsive cancellation and progress updates.
    /// Value: 4 MB.
    static let copyChunkSizeBytes: Int = 4 * 1024 * 1024

    /// Maximum number of times to retry a failed file copy before skipping
    /// the file and continuing with the rest of the session.
    static let maxCopyRetries: Int = 3

    /// Seconds to wait between retry attempts for a failed file copy.
    /// Gives transient errors (e.g. a brief USB hiccup) time to clear.
    static let retryDelaySeconds: Double = 2.0

    // MARK: - Module 4 — Verification

    /// Files larger than this threshold show per-byte verification progress
    /// in the UI. Files below this threshold show a brief spinner instead,
    /// because verification completes too quickly for a progress bar to be
    /// meaningful.
    /// Value: 10 MB.
    static let verificationProgressThresholdBytes: Int64 = 10 * 1024 * 1024

    // MARK: - Module 5 — Progress UI

    /// The rolling time window (in seconds) used to compute the average
    /// transfer rate for the estimated-time-remaining display. A shorter
    /// window is more responsive to speed changes; a longer window is
    /// smoother. 10 seconds is a good balance.
    static let transferRateWindowSeconds: Double = 10.0
}
