// CopyEngine.swift
// Virtual Backup Box
//
// Streams one file from source to destination in chunks, computing the
// SHA-256 hash of the source data on the fly. Returns the hash as a hex
// string on success. On any failure (read error, write error, cancellation),
// the partial destination file is deleted before throwing.
//
// This engine is nonisolated so it runs off the main thread. It does not
// retry — retry logic lives in BackupSessionService. It does not verify —
// verification is VerificationEngine's job.
//
// FileManager.copyItem is deliberately not used: it provides no progress
// reporting, no hash computation, and no cancellation checkpoints.

import Foundation
import CryptoKit

nonisolated enum CopyEngine {

    /// Errors that can occur during the copy stream.
    enum CopyError: Error {
        case sourceReadFailed
        case destinationWriteFailed
        case cancelled
    }

    /// Streams a file from source to destination, computing SHA-256 on the fly.
    ///
    /// - Parameters:
    ///   - source: Full URL of the source file (security-scoped access must
    ///     already be active).
    ///   - destination: Full URL where the file should be written.
    ///   - onProgress: Called after each chunk with cumulative bytes written.
    /// - Returns: The source file's SHA-256 hash as a lowercase hex string.
    /// - Throws: CopyError on read failure, write failure, or cancellation.
    ///   On any throw, the partial destination file is deleted.
    static func copyFile(
        from source: URL,
        to destination: URL,
        onProgress: @Sendable (Int64) -> Void
    ) async throws -> String {
        // Create destination directory if needed
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let inputStream = InputStream(url: source) else {
            throw CopyError.sourceReadFailed
        }
        guard let outputStream = OutputStream(url: destination, append: false) else {
            throw CopyError.destinationWriteFailed
        }

        inputStream.open()
        outputStream.open()

        var copySucceeded = false
        defer {
            inputStream.close()
            outputStream.close()
            if !copySucceeded {
                try? FileManager.default.removeItem(at: destination)
            }
        }

        var hasher = SHA256()
        let chunkSize = Constants.copyChunkSizeBytes
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        var totalBytesWritten: Int64 = 0

        while true {
            if Task.isCancelled { throw CopyError.cancelled }

            let bytesRead = inputStream.read(buffer, maxLength: chunkSize)
            if bytesRead < 0 { throw CopyError.sourceReadFailed }
            if bytesRead == 0 { break }

            // Feed chunk to hasher
            hasher.update(data: Data(bytes: buffer, count: bytesRead))

            // Write chunk — may require multiple writes if the output stream
            // accepts fewer bytes than requested (e.g. slow USB target).
            var offset = 0
            while offset < bytesRead {
                let written = outputStream.write(
                    buffer.advanced(by: offset),
                    maxLength: bytesRead - offset
                )
                if written < 0 { throw CopyError.destinationWriteFailed }
                offset += written
            }

            totalBytesWritten += Int64(bytesRead)
            onProgress(totalBytesWritten)

            // Yield to allow cancellation checks and other tasks to run
            await Task.yield()
        }

        let digest = hasher.finalize()
        let hexString = Data(digest).map { String(format: "%02x", $0) }.joined()

        copySucceeded = true
        return hexString
    }
}
