// ScanResult.swift
// Virtual Backup Box
//
// The aggregate output of a Module 2 source scan. Contains the categorised
// file lists, counts, and context needed by Module 3 to begin copying.
// This struct is not a SwiftData model — it exists only in memory.

import Foundation

/// The complete result of scanning a source folder against a target.
struct ScanResult: Sendable {

    /// Files that need to be copied and verified (not at destination).
    let filesToCopy: [SourceFile]

    /// Files that exist at the destination with matching size but have no
    /// database record. They will be hashed and recorded — no copy needed.
    /// This self-heals the database after reinstall or history clear.
    let filesToVerifyOnly: [SourceFile]

    /// Files that already have a verified database record — skipped entirely.
    let filesToSkip: [SourceFile]

    /// Number of macOS system files (e.g. .DS_Store) silently excluded.
    let excludedCount: Int

    /// Total bytes across all files that need copying.
    let totalBytesToCopy: Int64

    /// Total bytes across verify-only files (read for hashing, not copied).
    let totalBytesToVerify: Int64

    /// Source root URL for this scan (passed through to Module 3).
    let sourceRootURL: URL

    /// Target root URL for this scan (passed through to Module 3).
    let targetRootURL: URL

    /// Session folder name at the target root (passed through to Module 3).
    let sessionFolderName: String

    /// True when there is no work to do — all files are either verified in
    /// the database or already at the destination.
    var isFullyBackedUp: Bool {
        filesToCopy.isEmpty && filesToVerifyOnly.isEmpty
    }

    /// True when no files need copying but some need DB records created.
    var onlyNeedsVerification: Bool {
        filesToCopy.isEmpty && !filesToVerifyOnly.isEmpty
    }
}
