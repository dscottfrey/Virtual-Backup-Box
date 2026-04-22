// ScanResult.swift
// Virtual Backup Box
//
// The aggregate output of a Module 2 source scan. Contains the categorised
// file lists, counts, and context needed by Module 3 to begin copying.
// This struct is not a SwiftData model — it exists only in memory.

import Foundation

/// The complete result of scanning a source folder against a target.
struct ScanResult: Sendable {

    /// Files that need to be copied and verified (no verified copy exists).
    let filesToCopy: [SourceFile]

    /// Files that already have a verified copy at the destination — skipped.
    let filesToSkip: [SourceFile]

    /// Number of macOS system files (e.g. .DS_Store) silently excluded.
    let excludedCount: Int

    /// Total bytes across all files that need copying. Used by the summary
    /// screen and by Module 5 for overall progress tracking.
    let totalBytesToCopy: Int64

    /// Source root URL for this scan (passed through to Module 3).
    let sourceRootURL: URL

    /// Target root URL for this scan (passed through to Module 3).
    let targetRootURL: URL

    /// Session folder name at the target root (passed through to Module 3).
    let sessionFolderName: String

    /// True when every source file already has a verified copy — nothing
    /// to do. The summary screen shows a reassuring "all backed up" message.
    var isFullyBackedUp: Bool { filesToCopy.isEmpty }
}
