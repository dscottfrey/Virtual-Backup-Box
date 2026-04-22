// SourceScannerService.swift
// Virtual Backup Box
//
// Walks the source folder tree, applies exclusion rules, and categorises
// every file as either "copy" or "skip" by comparing against verified
// database records. The output is a ScanResult handed to Module 3.
//
// This service is nonisolated so it can run off the main thread via
// Task.detached. It never writes to the database or modifies any file —
// the scan is strictly read-only.

import Foundation

/// Lightweight snapshot of a verified FileRecord, used for the in-memory
/// comparison. Sendable so it can cross actor boundaries safely.
struct VerifiedFileInfo: Sendable {
    let fileSizeBytes: Int64
    let absoluteDestinationPath: String
}

nonisolated enum SourceScannerService {

    /// Scans the source folder, compares against verified records, and
    /// returns a categorised ScanResult.
    ///
    /// - Parameters:
    ///   - sourceURL: Root URL of the source folder.
    ///   - targetURL: Root URL of the backup target.
    ///   - sessionFolderName: Subfolder at the target for this session.
    ///   - cameraModel: Camera model string for settings file tagging.
    ///   - verifiedRecords: Pre-fetched DB records keyed by relative path.
    ///   - onProgress: Called periodically with the running file count.
    static func performScan(
        sourceURL: URL,
        targetURL: URL,
        sessionFolderName: String,
        cameraModel: String?,
        verifiedRecords: [String: VerifiedFileInfo],
        onProgress: @Sendable (Int) -> Void
    ) -> ScanResult {
        let (rawFiles, excludedCount) = enumerateSource(
            at: sourceURL,
            onProgress: onProgress
        )

        let (toCopy, toVerify, toSkip) = categoriseFiles(
            rawFiles,
            targetURL: targetURL,
            sessionFolderName: sessionFolderName,
            cameraModel: cameraModel,
            verifiedRecords: verifiedRecords
        )

        return ScanResult(
            filesToCopy: toCopy,
            filesToVerifyOnly: toVerify,
            filesToSkip: toSkip,
            excludedCount: excludedCount,
            totalBytesToCopy: toCopy.reduce(Int64(0)) { $0 + $1.fileSizeBytes },
            totalBytesToVerify: toVerify.reduce(Int64(0)) { $0 + $1.fileSizeBytes },
            sourceRootURL: sourceURL,
            targetRootURL: targetURL,
            sessionFolderName: sessionFolderName
        )
    }

    // MARK: - Step 1: Enumerate Source Files

    /// Walks the source tree, applies exclusion rules, and returns all
    /// regular files with their relative paths and sizes.
    private static func enumerateSource(
        at sourceURL: URL,
        onProgress: @Sendable (Int) -> Void
    ) -> (files: [(url: URL, relativePath: String, size: Int64)], excludedCount: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isDirectoryKey]

        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return ([], 0)
        }

        var files: [(url: URL, relativePath: String, size: Int64)] = []
        var excludedCount = 0
        let progressInterval = 50

        while let fileURL = enumerator.nextObject() as? URL {
            let name = fileURL.lastPathComponent

            // Exclude macOS system files and directories
            if Constants.excludedFilenames.contains(name)
                || name.hasPrefix(Constants.excludedFilePrefix) {
                let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                excludedCount += 1
                continue
            }

            // Only process regular files (not directories or symlinks)
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }

            let size = Int64(values?.fileSize ?? 0)
            let relative = DestinationPathService.relativePath(
                of: fileURL, relativeTo: sourceURL
            )
            files.append((fileURL, relative, size))

            if files.count % progressInterval == 0 {
                onProgress(files.count)
            }
        }

        onProgress(files.count)
        return (files, excludedCount)
    }

    // MARK: - Step 2: Categorise Files

    /// Compares each file against verified records and destination state.
    /// Files are sorted into three buckets:
    /// - copy: not at destination, needs full copy + verify
    /// - verifyOnly: at destination with matching size but no DB record,
    ///   needs hashing and a FileRecord created (self-heals the database)
    /// - skip: has a verified DB record, nothing to do
    private static func categoriseFiles(
        _ files: [(url: URL, relativePath: String, size: Int64)],
        targetURL: URL,
        sessionFolderName: String,
        cameraModel: String?,
        verifiedRecords: [String: VerifiedFileInfo]
    ) -> (toCopy: [SourceFile], toVerify: [SourceFile], toSkip: [SourceFile]) {
        var toCopy: [SourceFile] = []
        var toVerify: [SourceFile] = []
        var toSkip: [SourceFile] = []

        for (url, relativePath, size) in files {
            let destURL = DestinationPathService.destinationURL(
                relativePath: relativePath,
                targetRoot: targetURL,
                sessionFolderName: sessionFolderName
            )
            let isSettings = SettingsFilePatterns.isSettingsFile(
                relativePath: relativePath,
                cameraModel: cameraModel
            )
            let status = classifyFile(
                relativePath: relativePath,
                destURL: destURL,
                sourceFileSize: size,
                verifiedRecords: verifiedRecords
            )

            let file = SourceFile(
                url: url, relativePath: relativePath,
                fileSizeBytes: size, status: status,
                isSettingsFile: isSettings, destinationURL: destURL
            )

            switch status {
            case .copy: toCopy.append(file)
            case .verifyOnly: toVerify.append(file)
            case .skip: toSkip.append(file)
            }
        }

        return (toCopy, toVerify, toSkip)
    }

    /// Determines the status for one file by checking the destination
    /// filesystem and the database.
    /// - skip: DB record exists and destination file matches → fully good
    /// - verifyOnly: destination exists with matching size but no DB record
    ///   → needs hashing to create a record (self-heals after reinstall)
    /// - copy: destination doesn't exist or size doesn't match → full copy
    private static func classifyFile(
        relativePath: String,
        destURL: URL,
        sourceFileSize: Int64,
        verifiedRecords: [String: VerifiedFileInfo]
    ) -> FileStatus {
        // Check if destination file exists
        guard FileManager.default.fileExists(atPath: destURL.path) else {
            return .copy
        }

        let destValues = try? destURL.resourceValues(forKeys: [.fileSizeKey])
        let destSize = Int64(destValues?.fileSize ?? -1)

        // DB record exists with matching size → fully verified, skip
        if let record = verifiedRecords[relativePath],
           destSize == record.fileSizeBytes {
            return .skip
        }

        // No DB record but destination size matches source → verify only
        if destSize == sourceFileSize {
            return .verifyOnly
        }

        // Size mismatch (truncated/partial file) → re-copy
        return .copy
    }
}
