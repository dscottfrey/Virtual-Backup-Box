// BackupSessionService.swift
// Virtual Backup Box
//
// The session orchestrator that spans Modules 3 and 4. Iterates the file
// list from ScanResult, calls CopyEngine per file, passes results to
// VerificationEngine, manages retries on failure, and updates the
// CopySession database record throughout.
//
// This is the only place in the codebase that calls both CopyEngine and
// VerificationEngine. No View or ViewModel calls them directly.

import Foundation
import SwiftData

enum BackupSessionService {

    // MARK: - Failure Classification
    //
    // Categories of per-file failure surfaced to the user via the failure
    // alert. Added 2026-05-13 (Scott): "can we detect for 'card not
    // mounted' and report that as failure cause? (as opposed to say,
    // file unreadable, which will happen, in which case we would
    // 'continue backup', but that should be the failure cause if so.
    // Probably trap all other failure causes)".
    //
    // The mount-state cases override per-file errors because they
    // change what the user should do: a single .sourceReadError is a
    // skip-this-file situation; a .sourceNotMounted means the whole
    // session is bricked and the user should Cancel Session (or reconnect
    // and Continue). The reason string in the alert reflects this.

    /// Cause of a per-file failure after all copy/verify retries
    /// exhausted. Determined by determineFailureCause().
    enum FailureCause {
        case sourceNotMounted
        case destinationNotMounted
        case sourceReadError
        case destinationWriteError
        case verificationMismatch
        case unknown
    }

    /// What happened on a single copy+verify attempt. Used inside
    /// processFile to record the most recent attempt's outcome so the
    /// caller can categorise the overall failure.
    private enum AttemptOutcome {
        case succeeded
        case threwSourceReadFailed
        case threwDestinationWriteFailed
        case threwOther
        case verifyMismatch
    }

    /// Runs a complete backup session from start to finish.
    ///
    /// Creates a CopySession, processes each file (copy → verify → retry),
    /// updates progress on SessionViewModel, and finalises the session status.
    /// Cooperatively cancellable via Task.isCancelled.
    static func runSession(
        scanResult: ScanResult,
        selectedCard: KnownCard?,
        sessionViewModel: SessionViewModel,
        modelContext: ModelContext
    ) async {
        // Create the session record
        let session = CopySession(
            sourcePath: scanResult.sourceRootURL.path,
            targetPath: scanResult.targetRootURL.path,
            sessionFolderName: scanResult.sessionFolderName,
            sourceCard: selectedCard,
            totalFilesFound: scanResult.filesToCopy.count + scanResult.filesToSkip.count
        )
        session.filesSkipped = scanResult.filesToSkip.count
        modelContext.insert(session)

        // Initialise the ViewModel for the UI
        let copyCount = scanResult.filesToCopy.count
        let verifyCount = scanResult.filesToVerifyOnly.count
        sessionViewModel.totalFiles = copyCount + verifyCount
        sessionViewModel.totalBytesToProcess =
            scanResult.totalBytesToCopy + scanResult.totalBytesToVerify
        sessionViewModel.filesSkipped = scanResult.filesToSkip.count
        sessionViewModel.sessionStartDate = Date()

        let sourceRootPath = scanResult.sourceRootURL.path
        let log = DebugLogService.shared

        log.log("Session started: \(copyCount) to copy, \(verifyCount) to verify, \(scanResult.filesToSkip.count) skipped")
        log.log("Source: \(scanResult.sourceRootURL.path)")
        log.log("Target: \(scanResult.targetRootURL.path)/\(scanResult.sessionFolderName)")

        // Phase 1: Verify-only files (exist at destination, need DB records)
        for file in scanResult.filesToVerifyOnly {
            if Task.isCancelled {
                finalise(session: session, status: .interrupted,
                         selectedCard: selectedCard,
                         sessionViewModel: sessionViewModel)
                return
            }
            await verifyExistingFile(
                file,
                sourceRootPath: sourceRootPath,
                session: session,
                sessionViewModel: sessionViewModel,
                modelContext: modelContext
            )
            sessionViewModel.currentPhase = .idle
        }

        // Phase 2: Copy files (not at destination, full copy + verify)
        for file in scanResult.filesToCopy {
            if Task.isCancelled {
                finalise(session: session, status: .interrupted,
                         selectedCard: selectedCard,
                         sessionViewModel: sessionViewModel)
                return
            }

            let (succeeded, lastOutcome) = await processFile(
                file,
                sourceRootPath: sourceRootPath,
                session: session,
                sessionViewModel: sessionViewModel,
                modelContext: modelContext
            )

            // Cancellation lands here too: processFile returns false when
            // CopyEngine throws .cancelled. Check Task.isCancelled BEFORE
            // treating the false as a real per-file failure — otherwise
            // tapping Cancel surfaces a "File Could Not Be Backed Up"
            // dialog (Scott 2026-05-12), which is misleading and demands
            // a "Continue Backup" decision the user has already declined.
            if Task.isCancelled {
                finalise(session: session, status: .interrupted,
                         selectedCard: selectedCard,
                         sessionViewModel: sessionViewModel)
                return
            }

            if !succeeded {
                session.filesFailed += 1
                sessionViewModel.filesFailed += 1

                let cause = determineFailureCause(
                    outcome: lastOutcome,
                    sourceURL: scanResult.sourceRootURL,
                    targetURL: scanResult.targetRootURL
                )
                let reason = failureReason(for: cause)
                sessionViewModel.failedFiles.append(
                    (relativePath: file.relativePath, reason: reason)
                )
                sessionViewModel.pendingFailureAlert = FailureAlert(
                    relativeFilePath: file.relativePath,
                    reason: reason
                )
                await sessionViewModel.waitForFailureDismissal()
            }

            sessionViewModel.currentPhase = .idle
        }

        // Determine final status
        let status: SessionStatus = session.filesFailed > 0
            ? .partialSuccess : .success
        log.log("Session finished: \(status.rawValue) — \(session.filesCopied) copied, \(session.filesFailed) failed, \(session.filesSkipped) skipped")
        finalise(session: session, status: status,
                 selectedCard: selectedCard,
                 sessionViewModel: sessionViewModel)
    }

    // MARK: - Verify-Only Processing

    /// Hashes an existing destination file and creates a FileRecord.
    /// No copy is performed — the file is already at the destination.
    /// This self-heals the database after reinstall or history clear.
    private static func verifyExistingFile(
        _ file: SourceFile,
        sourceRootPath: String,
        session: CopySession,
        sessionViewModel: SessionViewModel,
        modelContext: ModelContext
    ) async {
        let fileName = file.relativePath
        let totalBytes = file.fileSizeBytes

        sessionViewModel.currentPhase = .verifying(
            fileName: fileName, bytesRead: 0, totalBytes: totalBytes
        )

        let result = await VerificationEngine.verifyExisting(
            destinationURL: file.destinationURL,
            sourceFile: file,
            sourceRootPath: sourceRootPath,
            session: session,
            context: modelContext
        ) { bytesRead in
            Task { @MainActor in
                sessionViewModel.currentPhase = .verifying(
                    fileName: fileName,
                    bytesRead: bytesRead,
                    totalBytes: totalBytes
                )
            }
        }

        switch result {
        case .success:
            session.filesCopied += 1
            sessionViewModel.filesCompleted += 1
            sessionViewModel.totalBytesWritten += file.fileSizeBytes
        case .failure:
            // Verify-only failure is unusual — file existed but couldn't
            // be read. Record as failed but don't block the session.
            session.filesFailed += 1
            sessionViewModel.filesFailed += 1
        }
    }

    // MARK: - Per-File Processing

    /// Attempts to copy and verify one file, retrying up to maxCopyRetries
    /// times on failure. Returns a tuple of (succeeded, lastOutcome) — the
    /// outcome records what happened on the most recent attempt so the
    /// caller can categorise the overall failure for the user.
    private static func processFile(
        _ file: SourceFile,
        sourceRootPath: String,
        session: CopySession,
        sessionViewModel: SessionViewModel,
        modelContext: ModelContext
    ) async -> (Bool, AttemptOutcome) {
        var lastOutcome: AttemptOutcome = .threwOther

        for attempt in 1...Constants.maxCopyRetries {
            if Task.isCancelled { return (false, lastOutcome) }

            do {
                // Copy phase
                let fileName = file.relativePath
                let totalBytes = file.fileSizeBytes

                sessionViewModel.currentPhase = .copying(
                    fileName: fileName, bytesWritten: 0, totalBytes: totalBytes
                )

                let sourceHash = try await CopyEngine.copyFile(
                    from: file.url,
                    to: file.destinationURL
                ) { bytesWritten in
                    Task { @MainActor in
                        sessionViewModel.currentPhase = .copying(
                            fileName: fileName,
                            bytesWritten: bytesWritten,
                            totalBytes: totalBytes
                        )
                    }
                }

                // Verify phase
                sessionViewModel.currentPhase = .verifying(
                    fileName: fileName, bytesRead: 0, totalBytes: totalBytes
                )

                let result = await VerificationEngine.verify(
                    sourceHash: sourceHash,
                    destinationURL: file.destinationURL,
                    sourceFile: file,
                    sourceRootPath: sourceRootPath,
                    session: session,
                    context: modelContext
                ) { bytesRead in
                    Task { @MainActor in
                        sessionViewModel.currentPhase = .verifying(
                            fileName: fileName,
                            bytesRead: bytesRead,
                            totalBytes: totalBytes
                        )
                    }
                }

                switch result {
                case .success:
                    session.filesCopied += 1
                    sessionViewModel.filesCompleted += 1
                    sessionViewModel.totalBytesWritten += file.fileSizeBytes
                    return (true, .succeeded)

                case .failure:
                    lastOutcome = .verifyMismatch
                    DebugLogService.shared.log(
                        "[BackupSession] verify failed attempt \(attempt)/\(Constants.maxCopyRetries) for \(file.relativePath)"
                    )
                    if attempt < Constants.maxCopyRetries {
                        try? await Task.sleep(for: .seconds(
                            Constants.retryDelaySeconds
                        ))
                    }
                }
            } catch {
                // Cancellation reaches us via CopyEngine throwing
                // .cancelled. Bail out immediately rather than logging
                // it as a copy failure and burning a retry cycle.
                if Task.isCancelled {
                    DebugLogService.shared.log(
                        "[BackupSession] cancelled during \(file.relativePath)"
                    )
                    return (false, lastOutcome)
                }

                // Map the CopyError to an AttemptOutcome so the caller
                // can build a specific failure reason. Anything other
                // than the named CopyError cases becomes .threwOther.
                lastOutcome = outcomeFor(error: error)

                // Catch was silent before 2026-05-12 — Scott hit a "Could
                // not be backed up after 3 attempts" with no log line
                // explaining which error fired. Logging the error type and
                // URL is the minimum to diagnose the next failure.
                DebugLogService.shared.log(
                    "[BackupSession] copy failed attempt \(attempt)/\(Constants.maxCopyRetries) for \(file.relativePath): \(error) — source=\(file.url.path)"
                )
                if attempt < Constants.maxCopyRetries {
                    try? await Task.sleep(for: .seconds(
                        Constants.retryDelaySeconds
                    ))
                }
            }
        }
        return (false, lastOutcome)
    }

    /// Translates a CopyEngine throw into the matching AttemptOutcome.
    /// Unrecognised errors map to .threwOther — they'll surface as
    /// .unknown in the user-facing cause.
    private static func outcomeFor(error: Error) -> AttemptOutcome {
        if let copyError = error as? CopyEngine.CopyError {
            switch copyError {
            case .sourceReadFailed: return .threwSourceReadFailed
            case .destinationWriteFailed: return .threwDestinationWriteFailed
            case .cancelled: return .threwOther
            }
        }
        return .threwOther
    }

    // MARK: - Session Finalisation

    /// Sets the final status on the session, updates the card's last backup
    /// date, and notifies the ViewModel that the session is complete.
    private static func finalise(
        session: CopySession,
        status: SessionStatus,
        selectedCard: KnownCard?,
        sessionViewModel: SessionViewModel
    ) {
        session.endDate = Date()
        session.status = status

        if status == .success {
            selectedCard?.lastBackupDate = Date()
        }

        sessionViewModel.isSessionComplete = true
        sessionViewModel.completedSession = session
    }

    // MARK: - Failure Cause Classification

    /// Decides which FailureCause to surface to the user. Mount-state
    /// checks come first because they override per-file errors:
    /// .sourceReadFailed when the whole card is gone is really
    /// .sourceNotMounted, and we want the user to act on that fact
    /// rather than thinking one file is broken.
    ///
    /// checkResourceIsReachable on a removable volume returns false
    /// shortly after the volume's mount path disappears, even before
    /// the security-scoped resource layer has caught up. That's the
    /// behaviour we want here — the canonical signal that "the drive
    /// is gone right now."
    private static func determineFailureCause(
        outcome: AttemptOutcome,
        sourceURL: URL,
        targetURL: URL
    ) -> FailureCause {
        let sourceReachable = (try? sourceURL.checkResourceIsReachable())
            ?? false
        let targetReachable = (try? targetURL.checkResourceIsReachable())
            ?? false

        if !sourceReachable { return .sourceNotMounted }
        if !targetReachable { return .destinationNotMounted }

        switch outcome {
        case .threwSourceReadFailed: return .sourceReadError
        case .threwDestinationWriteFailed: return .destinationWriteError
        case .verifyMismatch: return .verificationMismatch
        case .threwOther, .succeeded: return .unknown
        }
    }

    /// Builds the human-readable reason string shown in the failure
    /// alert and recorded on the failed-files list. Phrased so the
    /// user can decide between Continue Backup (skip this file, keep
    /// going) and Cancel Session — the recoverable single-file cases
    /// are explicitly OK to continue; the mount-disconnected cases
    /// strongly suggest Cancel.
    private static func failureReason(for cause: FailureCause) -> String {
        let retries = Constants.maxCopyRetries
        switch cause {
        case .sourceNotMounted:
            return "The source has been disconnected. Reconnect it and tap Continue Backup, or Cancel Session."
        case .destinationNotMounted:
            return "The destination has been disconnected. Reconnect it and tap Continue Backup, or Cancel Session."
        case .sourceReadError:
            return "This file could not be read from the source after \(retries) attempts. Continue Backup will skip this file."
        case .destinationWriteError:
            return "This file could not be written to the destination after \(retries) attempts. Continue Backup will skip this file."
        case .verificationMismatch:
            return "The copy completed but verification failed after \(retries) attempts — the destination file does not match the source. Continue Backup will skip this file."
        case .unknown:
            return "Could not be backed up after \(retries) attempts. Continue Backup will skip this file."
        }
    }
}
