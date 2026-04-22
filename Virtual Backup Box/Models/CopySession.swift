// CopySession.swift
// Virtual Backup Box
//
// One record per backup session — from the moment "Start Backup" is tapped
// to the moment the session ends (success, partial success, or interruption).
//
// A session always has a source path and a target path. If the source is a
// known camera card, sourceCard is populated and the session folder name comes
// from the card's destinationFolderName. If the source is a generic folder
// (no DCIM detected), sourceCard is nil and the session folder name is the
// source folder's own name.
//
// The target is identified by its path string, not by a SwiftData relationship
// to KnownTarget. This is deliberate: it avoids complications if a target is
// renamed, removed, or its bookmark becomes stale while sessions still
// reference it. See the Model Relationships section of 00_DATA_MODELS.md.

import Foundation
import SwiftData

// MARK: - SessionStatus

/// The possible outcomes of a CopySession.
/// Raw-value String for automatic Codable conformance with SwiftData.
enum SessionStatus: String, Codable {
    /// Session is currently running. Set at session creation, before any
    /// files are copied.
    case inProgress

    /// All files were copied and verified with no failures.
    case success

    /// Session completed but one or more files failed after all retries.
    case partialSuccess

    /// Session stopped before completion — user cancelled, card removed,
    /// or app was terminated.
    case interrupted
}

// MARK: - CopySession

@Model
final class CopySession {

    // MARK: - Stored Properties

    /// When the session started (set at creation).
    var startDate: Date

    /// When the session ended. Nil while the session is in progress.
    var endDate: Date?

    /// Absolute path string of the source root folder selected for this session.
    /// Example: "/var/mobile/Containers/..." or a volume path for a camera card.
    var sourcePath: String

    /// Absolute path string of the target root folder for this session.
    /// Example: "/Volumes/Samsung T7/Backups"
    var targetPath: String

    /// The session folder created at the target root for this session's files.
    /// For camera cards: the card's destinationFolderName
    ///   (e.g. "20260421_EOS R6 Mark III Card-1").
    /// For generic folders: the source folder's own name (e.g. "WorkingFiles").
    var sessionFolderName: String

    /// Overall outcome of the session. Starts as .inProgress and is updated
    /// to a final value when the session ends.
    var status: SessionStatus

    /// Whether source files were deleted from iPad storage after a successful
    /// session (Module 6 cleanup offer). Defaults to false.
    var sourceFilesDeleted: Bool

    // MARK: - Relationships

    /// The known card this session backed up, if the source was detected as
    /// a camera card. Nil for generic folder sources.
    var sourceCard: KnownCard?

    /// All file-level records for this session. One FileRecord per successfully
    /// verified file. Failed files do not produce FileRecords.
    /// Cascade delete: removing a CopySession removes all its FileRecords.
    @Relationship(deleteRule: .cascade, inverse: \FileRecord.session)
    var fileRecords: [FileRecord] = []

    // MARK: - Convenience Counters

    /// These counters are updated incrementally as files are processed, so
    /// the UI can display live progress without querying the fileRecords array.

    /// Total number of files found during the Module 2 scan.
    var totalFilesFound: Int

    /// Files successfully copied and verified in this session.
    var filesCopied: Int

    /// Files skipped because they were already backed up (verified in a
    /// previous session, confirmed by Module 2 incremental comparison).
    var filesSkipped: Int

    /// Files that failed after all retry attempts.
    var filesFailed: Int

    // MARK: - Initialiser

    /// Creates a new CopySession record.
    ///
    /// Called by BackupSessionService (Module 3) at the start of every
    /// backup session, before any files are copied.
    ///
    /// - Parameters:
    ///   - sourcePath: Absolute path of the source root folder.
    ///   - targetPath: Absolute path of the target root folder.
    ///   - sessionFolderName: The subfolder at the target where files go.
    ///   - sourceCard: The KnownCard record, if the source is a camera card.
    ///   - totalFilesFound: Total file count from the Module 2 scan.
    init(sourcePath: String,
         targetPath: String,
         sessionFolderName: String,
         sourceCard: KnownCard? = nil,
         totalFilesFound: Int = 0) {
        self.startDate = Date()
        self.endDate = nil
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.sessionFolderName = sessionFolderName
        self.sourceCard = sourceCard
        self.totalFilesFound = totalFilesFound
        self.status = .inProgress
        self.sourceFilesDeleted = false
        self.filesCopied = 0
        self.filesSkipped = 0
        self.filesFailed = 0
    }
}
