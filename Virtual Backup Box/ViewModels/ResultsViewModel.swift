// ResultsViewModel.swift
// Virtual Backup Box
//
// Wraps a completed CopySession and provides computed display strings for
// the post-session results screen. Also manages the source cleanup offer
// state (the "Remove from iPad?" flow after a 100% successful session).
//
// This ViewModel reads from the CopySession and SessionViewModel but does
// not modify the database except for the cleanup deletion.

import Foundation
import SwiftData
import Observation

@Observable
class ResultsViewModel {

    let session: CopySession
    let failedFiles: [(relativePath: String, reason: String)]
    let targetName: String
    private let modelContext: ModelContext

    // MARK: - Cleanup State

    /// Whether the cleanup confirmation sheet is showing.
    var showCleanupConfirmation = false

    /// Whether the cleanup has been performed.
    var cleanupCompleted = false

    /// Message shown after cleanup completes (e.g. "18.7 GB removed").
    var cleanupMessage = ""

    // MARK: - Init

    init(session: CopySession,
         failedFiles: [(relativePath: String, reason: String)],
         targetName: String,
         modelContext: ModelContext) {
        self.session = session
        self.failedFiles = failedFiles
        self.targetName = targetName
        self.modelContext = modelContext
    }

    // MARK: - Display Properties

    var totalBytesCopied: Int64 {
        session.fileRecords.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
    }

    var formattedBytesCopied: String {
        ByteCountFormatter.string(fromByteCount: totalBytesCopied, countStyle: .file)
    }

    var sessionDuration: String {
        guard let end = session.endDate else { return "" }
        let seconds = Int(end.timeIntervalSince(session.startDate))
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes == 0 { return "\(secs) seconds" }
        return "\(minutes) minutes \(secs) seconds"
    }

    var destinationDisplay: String {
        let target = targetName.isEmpty ? "target" : targetName
        return "\(target) \u{203A} \(session.sessionFolderName)"
    }

    // MARK: - Cleanup Eligibility

    /// True if the source is internal iPad storage (not a camera card, not
    /// external). Uses URLResourceKey.volumeIsInternalKey to determine this.
    var sourceIsInternalStorage: Bool {
        guard session.sourceCard == nil else { return false }
        let url = URL(fileURLWithPath: session.sourcePath)
        let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey])
        return values?.volumeIsInternal ?? false
    }

    /// True when the cleanup offer should be shown: 100% success, source
    /// is internal storage, cleanup not already performed.
    var showCleanupOffer: Bool {
        session.status == .success
            && sourceIsInternalStorage
            && !cleanupCompleted
            && !session.sourceFilesDeleted
    }

    // MARK: - Cleanup Action

    /// Deletes the backed-up source files from internal iPad storage.
    ///
    /// DELIBERATE EXCEPTION to read-only source rule (§2 of overall directive).
    /// This deletion is triggered only by explicit user confirmation after a
    /// 100% successful backup session. See SessionResultsView cleanup offer.
    func performSourceCleanup() {
        var deletedBytes: Int64 = 0

        for record in session.fileRecords {
            let sourceURL = URL(fileURLWithPath: record.absoluteSourceRoot)
                .appendingPathComponent(record.relativeSourcePath)

            // DELIBERATE EXCEPTION to read-only source rule (§2).
            // Deletion is user-confirmed after verified backup.
            do {
                try FileManager.default.removeItem(at: sourceURL)
                deletedBytes += record.fileSizeBytes
            } catch {
                // If individual file deletion fails, continue with others.
                // The user can manually clean up any remaining files.
            }
        }

        session.sourceFilesDeleted = true
        cleanupCompleted = true
        cleanupMessage = "\(ByteCountFormatter.string(fromByteCount: deletedBytes, countStyle: .file)) removed from iPad storage."
    }
}
