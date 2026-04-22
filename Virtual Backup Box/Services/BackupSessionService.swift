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
        sessionViewModel.totalFiles = scanResult.filesToCopy.count
        sessionViewModel.totalBytesToProcess = scanResult.totalBytesToCopy
        sessionViewModel.filesSkipped = scanResult.filesToSkip.count
        sessionViewModel.sessionStartDate = Date()

        let sourceRootPath = scanResult.sourceRootURL.path

        // Process each file
        for file in scanResult.filesToCopy {
            if Task.isCancelled {
                finalise(session: session, status: .interrupted,
                         selectedCard: selectedCard,
                         sessionViewModel: sessionViewModel)
                return
            }

            let succeeded = await processFile(
                file,
                sourceRootPath: sourceRootPath,
                session: session,
                sessionViewModel: sessionViewModel,
                modelContext: modelContext
            )

            if !succeeded {
                session.filesFailed += 1
                sessionViewModel.filesFailed += 1

                let reason = failureReason(for: file)
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
        finalise(session: session, status: status,
                 selectedCard: selectedCard,
                 sessionViewModel: sessionViewModel)
    }

    // MARK: - Per-File Processing

    /// Attempts to copy and verify one file, retrying up to maxCopyRetries
    /// times on failure. Returns true if the file was successfully verified.
    private static func processFile(
        _ file: SourceFile,
        sourceRootPath: String,
        session: CopySession,
        sessionViewModel: SessionViewModel,
        modelContext: ModelContext
    ) async -> Bool {
        for attempt in 1...Constants.maxCopyRetries {
            if Task.isCancelled { return false }

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
                    return true

                case .failure:
                    if attempt < Constants.maxCopyRetries {
                        try? await Task.sleep(for: .seconds(
                            Constants.retryDelaySeconds
                        ))
                    }
                }
            } catch {
                // Copy failed — retry after delay
                if attempt < Constants.maxCopyRetries {
                    try? await Task.sleep(for: .seconds(
                        Constants.retryDelaySeconds
                    ))
                }
            }
        }
        return false
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

    /// Builds a human-readable failure reason for the alert.
    private static func failureReason(for file: SourceFile) -> String {
        "Could not be backed up after \(Constants.maxCopyRetries) attempts."
    }
}
