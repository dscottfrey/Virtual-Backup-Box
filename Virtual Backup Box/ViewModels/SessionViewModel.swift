// SessionViewModel.swift
// Virtual Backup Box
//
// Observable state holder for a running backup session. Views (Module 5)
// bind to these properties to display live progress. BackupSessionService
// writes to them as it processes files.
//
// This ViewModel contains no business logic — it is a data bridge between
// BackupSessionService (which does the work) and the progress UI (which
// displays it).

import Foundation
import SwiftData
import Observation

/// The current phase of a single file being processed.
enum SessionPhase: Sendable {
    case copying(fileName: String, bytesWritten: Int64, totalBytes: Int64)
    case verifying(fileName: String, bytesRead: Int64, totalBytes: Int64)
    case idle
}

/// Information about a file that failed after all retry attempts.
struct FailureAlert: Identifiable, Sendable {
    let id = UUID()
    let relativeFilePath: String
    let reason: String
}

@Observable
class SessionViewModel {

    // MARK: - Per-File Progress

    /// What the engine is doing right now (copying, verifying, or idle).
    var currentPhase: SessionPhase = .idle

    // MARK: - Session-Level Progress

    /// Files successfully copied and verified this session.
    var filesCompleted = 0

    /// Files that failed after all retries this session.
    var filesFailed = 0

    /// Files skipped because they were already backed up (from Module 2).
    var filesSkipped = 0

    /// Total files that need copying (from ScanResult).
    var totalFiles = 0

    /// Cumulative bytes written across all files so far.
    var totalBytesWritten: Int64 = 0

    /// Total bytes across all files that need copying.
    var totalBytesToProcess: Int64 = 0

    /// When the session started (for elapsed time calculation).
    var sessionStartDate = Date()

    // MARK: - Failure Alert

    /// Non-nil when a file has failed and the user must acknowledge it.
    /// The session pauses until this is dismissed.
    var pendingFailureAlert: FailureAlert?

    /// Continuation that BackupSessionService awaits while the failure
    /// alert is showing. Resumed when the user dismisses the alert.
    private var failureContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Failed Files (for results screen)

    /// List of files that failed, with reasons. Populated during the session
    /// and displayed on the post-session results screen. Not persisted —
    /// only available for the session that just completed.
    var failedFiles: [(relativePath: String, reason: String)] = []

    /// Friendly name of the backup target (e.g. "Samsung T7"). Set at
    /// session start for display on the results screen.
    var targetName = ""

    // MARK: - Session Lifecycle

    /// True when the session has finished (success, partial, or interrupted).
    var isSessionComplete = false

    /// The completed CopySession record. Set when the session ends.
    var completedSession: CopySession?

    /// The Task running the backup, stored so it can be cancelled.
    private var sessionTask: Task<Void, Never>?

    // MARK: - Actions

    /// Starts the backup session in a background-capable Task.
    func startSession(
        scanResult: ScanResult,
        selectedCard: KnownCard?,
        modelContext: ModelContext
    ) {
        sessionTask = Task {
            await BackupSessionService.runSession(
                scanResult: scanResult,
                selectedCard: selectedCard,
                sessionViewModel: self,
                modelContext: modelContext
            )
        }
    }

    /// Cancels the running session. The current file finishes cleanly,
    /// then the session stops and is marked as interrupted.
    func cancelSession() {
        sessionTask?.cancel()
    }

    /// Called by BackupSessionService when a file fails. Suspends the
    /// session until the user dismisses the failure alert.
    func waitForFailureDismissal() async {
        await withCheckedContinuation { continuation in
            failureContinuation = continuation
        }
    }

    /// Called by the UI when the user taps "Continue Backup" on the
    /// failure alert. Resumes the session.
    func dismissFailureAlert() {
        pendingFailureAlert = nil
        failureContinuation?.resume()
        failureContinuation = nil
    }
}
