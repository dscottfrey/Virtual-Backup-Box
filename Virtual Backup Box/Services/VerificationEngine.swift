// VerificationEngine.swift
// Virtual Backup Box
//
// Reads the destination file after copy, computes its SHA-256 hash, and
// compares it to the source hash produced by CopyEngine. On a match,
// writes a FileRecord to SwiftData. On a mismatch, deletes the corrupt
// destination file.
//
// This is the only place in the codebase that writes FileRecord entries.
//
// The verify() method runs on MainActor (for SwiftData access) but
// dispatches the heavy I/O (hashing) to a nonisolated async function
// that runs off the main thread.

import Foundation
import CryptoKit
import SwiftData

/// The outcome of verifying one file.
enum VerificationResult {
    case success(FileRecord)
    case failure(VerificationError)
}

/// Errors that can occur during verification.
enum VerificationError: Error {
    case hashMismatch(sourceHash: String, destinationHash: String)
    case destinationReadError(underlying: Error)
    case destinationNotFound
}

enum VerificationEngine {

    /// Verifies a copied file by hashing the destination and comparing to
    /// the source hash. On match, creates and inserts a FileRecord.
    ///
    /// Runs on MainActor (for ModelContext access). The actual file hashing
    /// runs off the main thread via the nonisolated hashFile helper.
    static func verify(
        sourceHash: String,
        destinationURL: URL,
        sourceFile: SourceFile,
        sourceRootPath: String,
        session: CopySession,
        context: ModelContext,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async -> VerificationResult {
        // Hash the destination file off the main thread
        let destHash: String
        do {
            destHash = try await hashFile(at: destinationURL, onProgress: onProgress)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            return .failure(.destinationReadError(underlying: error))
        }

        // Compare hashes
        guard destHash == sourceHash else {
            try? FileManager.default.removeItem(at: destinationURL)
            return .failure(.hashMismatch(
                sourceHash: sourceHash,
                destinationHash: destHash
            ))
        }

        // Match — create FileRecord (on MainActor, using ModelContext)
        let record = FileRecord(
            relativeSourcePath: sourceFile.relativePath,
            absoluteSourceRoot: sourceRootPath,
            absoluteDestinationPath: destinationURL.path,
            sha256Hash: sourceHash,
            fileSizeBytes: sourceFile.fileSizeBytes,
            isSettingsFile: sourceFile.isSettingsFile
        )
        record.session = session
        context.insert(record)

        return .success(record)
    }

    /// Verifies an existing destination file that has no database record.
    ///
    /// Hashes the destination file and creates a FileRecord so the database
    /// self-heals after a reinstall or history clear. No copy is performed —
    /// the file is already at the destination with the correct size.
    ///
    /// The hash stored is the destination file's hash (which is the only
    /// copy we have access to). This is correct: the destination IS the
    /// verified copy.
    static func verifyExisting(
        destinationURL: URL,
        sourceFile: SourceFile,
        sourceRootPath: String,
        session: CopySession,
        context: ModelContext,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async -> VerificationResult {
        let destHash: String
        do {
            destHash = try await hashFile(
                at: destinationURL, onProgress: onProgress
            )
        } catch {
            return .failure(.destinationReadError(underlying: error))
        }

        let record = FileRecord(
            relativeSourcePath: sourceFile.relativePath,
            absoluteSourceRoot: sourceRootPath,
            absoluteDestinationPath: destinationURL.path,
            sha256Hash: destHash,
            fileSizeBytes: sourceFile.fileSizeBytes,
            isSettingsFile: sourceFile.isSettingsFile
        )
        record.session = session
        context.insert(record)

        return .success(record)
    }

    // MARK: - Private: File Hashing

    /// Reads a file in chunks and computes its SHA-256 hash.
    ///
    /// Nonisolated so it runs off the main thread when called with await
    /// from a MainActor context.
    nonisolated private static func hashFile(
        at url: URL,
        onProgress: @Sendable (Int64) -> Void
    ) async throws -> String {
        guard let inputStream = InputStream(url: url) else {
            throw VerificationError.destinationNotFound
        }

        inputStream.open()
        defer { inputStream.close() }

        var hasher = SHA256()
        let chunkSize = Constants.copyChunkSizeBytes
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        var totalBytesRead: Int64 = 0

        while true {
            if Task.isCancelled { break }

            let bytesRead = inputStream.read(buffer, maxLength: chunkSize)
            if bytesRead < 0 {
                throw VerificationError.destinationReadError(
                    underlying: inputStream.streamError
                        ?? NSError(domain: "VerificationEngine", code: -1)
                )
            }
            if bytesRead == 0 { break }

            hasher.update(data: Data(bytes: buffer, count: bytesRead))
            totalBytesRead += Int64(bytesRead)
            onProgress(totalBytesRead)

            await Task.yield()
        }

        let digest = hasher.finalize()
        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }
}
