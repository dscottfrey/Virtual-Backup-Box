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

        let (toCopy, toSkip) = categoriseFiles(
            rawFiles,
            targetURL: targetURL,
            sessionFolderName: sessionFolderName,
            cameraModel: cameraModel,
            verifiedRecords: verifiedRecords
        )

        let totalBytes = toCopy.reduce(Int64(0)) { $0 + $1.fileSizeBytes }

        return ScanResult(
            filesToCopy: toCopy,
            filesToSkip: toSkip,
            excludedCount: excludedCount,
            totalBytesToCopy: totalBytes,
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

    /// Compares each file against verified records and destination state
    /// to determine whether it should be copied or skipped.
    private static func categoriseFiles(
        _ files: [(url: URL, relativePath: String, size: Int64)],
        targetURL: URL,
        sessionFolderName: String,
        cameraModel: String?,
        verifiedRecords: [String: VerifiedFileInfo]
    ) -> (toCopy: [SourceFile], toSkip: [SourceFile]) {
        var toCopy: [SourceFile] = []
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

            if shouldSkip(relativePath: relativePath, destURL: destURL,
                          verifiedRecords: verifiedRecords) {
                toSkip.append(SourceFile(
                    url: url, relativePath: relativePath,
                    fileSizeBytes: size, status: .skip,
                    isSettingsFile: isSettings, destinationURL: destURL
                ))
            } else {
                toCopy.append(SourceFile(
                    url: url, relativePath: relativePath,
                    fileSizeBytes: size, status: .copy,
                    isSettingsFile: isSettings, destinationURL: destURL
                ))
            }
        }

        return (toCopy, toSkip)
    }

    /// Determines if a file can be skipped. All three conditions must be true:
    /// 1. A verified DB record exists for this relative path.
    /// 2. The record's destination path matches our computed destination.
    /// 3. The destination file exists and its size matches the record.
    private static func shouldSkip(
        relativePath: String,
        destURL: URL,
        verifiedRecords: [String: VerifiedFileInfo]
    ) -> Bool {
        guard let record = verifiedRecords[relativePath],
              record.absoluteDestinationPath == destURL.path,
              FileManager.default.fileExists(atPath: destURL.path) else {
            return false
        }
        let destValues = try? destURL.resourceValues(forKeys: [.fileSizeKey])
        let destSize = Int64(destValues?.fileSize ?? -1)
        return destSize == record.fileSizeBytes
    }
}
