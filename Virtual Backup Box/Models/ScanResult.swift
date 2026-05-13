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

    /// Files detected during scan that live in iCloud and have NOT been
    /// downloaded to this device. Their relative paths are kept so the
    /// scan-summary UI can name a few in the warning message. When this
    /// is non-empty the session is blocked from starting — the user is
    /// asked to download the files first. See §5c-extension (2026-05-13).
    ///
    /// Note: third-party file-provider sources (Dropbox, Synology, Box)
    /// do not surface a notDownloaded status via the iCloud resource key
    /// and so will not appear here. Those fall through to the copy
    /// engine's existing retry-then-skip path with a per-file warning.
    let cloudOnlyFiles: [String]

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
    /// the database or already at the destination. Does not consider
    /// cloud-only files; check hasCloudOnlyBlock separately.
    var isFullyBackedUp: Bool {
        filesToCopy.isEmpty && filesToVerifyOnly.isEmpty
    }

    /// True when no files need copying but some need DB records created.
    var onlyNeedsVerification: Bool {
        filesToCopy.isEmpty && !filesToVerifyOnly.isEmpty
    }

    /// True when the session must be blocked because some source files
    /// are not downloaded to this device.
    var hasCloudOnlyBlock: Bool {
        !cloudOnlyFiles.isEmpty
    }
}
