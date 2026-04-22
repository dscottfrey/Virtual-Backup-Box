// FileRecord.swift
// Virtual Backup Box
//
// One record per file that has been successfully copied and verified in a
// backup session. This is the core of the incremental backup system.
//
// On subsequent runs against the same source, Module 2 fetches all FileRecords
// for the source/target path combination and uses them to determine which files
// already have a verified copy at the destination. If a FileRecord exists with
// a matching relative path and the destination file's size matches, the file
// is skipped — no redundant copy, no redundant hash.
//
// A FileRecord is written ONLY after successful verification (source SHA-256
// hash == destination SHA-256 hash). Failed copies never produce a FileRecord.
// This means the absence of a FileRecord for a given file always means
// "not yet verified" — there is no ambiguity.

import Foundation
import SwiftData

@Model
final class FileRecord {

    // MARK: - Stored Properties

    /// Path of the source file, relative to the session source root.
    /// Example: "DCIM/100EOSR6/_MG_1530.CR3"
    /// Used by Module 2 for incremental comparison: look up this path in
    /// the database to see if it was already backed up.
    var relativeSourcePath: String

    /// Absolute path of the source root at time of copy.
    /// Combined with relativeSourcePath to reconstruct the full source URL.
    /// Example: "/var/mobile/Containers/.../card-root/"
    var absoluteSourceRoot: String

    /// Absolute path of the destination file (full path, not relative).
    /// Example: "/Volumes/T7/20260421_EOS R6 Mark III Card-1/DCIM/100EOSR6/_MG_1530.CR3"
    var absoluteDestinationPath: String

    /// SHA-256 hash of the source file, computed during the copy stream by
    /// Module 3 and confirmed to match the destination by Module 4.
    /// Stored as a lowercase hex string (64 characters).
    /// We store the source hash (not the destination hash) because they are
    /// equal after verification, and the source hash is what Module 2 would
    /// compare against if performing a Deep Verify in the future.
    var sha256Hash: String

    /// File size in bytes, as reported by the filesystem at time of copy.
    /// Used by Module 2 as a quick sanity check before trusting the database
    /// record: if the destination file's current size doesn't match this
    /// stored value, the file is re-copied and re-verified.
    var fileSizeBytes: Int64

    /// When this file was successfully verified (hash match confirmed).
    var verifiedDate: Date

    /// True if this file was identified as a camera settings file during the
    /// Module 2 scan (e.g. .CSD files at the card root for Canon cameras).
    /// Used by the settings restore stretch goal (§9.1) to query settings
    /// files separately from media files.
    var isSettingsFile: Bool

    // MARK: - Relationships

    /// The session this file was copied and verified in.
    var session: CopySession?

    // MARK: - Initialiser

    /// Creates a new FileRecord after successful verification.
    ///
    /// Called only by VerificationEngine (Module 4) when the destination
    /// file's SHA-256 hash matches the source hash.
    ///
    /// - Parameters:
    ///   - relativeSourcePath: File path relative to the source root.
    ///   - absoluteSourceRoot: Absolute path of the source root folder.
    ///   - absoluteDestinationPath: Absolute path of the destination file.
    ///   - sha256Hash: Verified SHA-256 hash (hex string, 64 characters).
    ///   - fileSizeBytes: File size in bytes at time of copy.
    ///   - isSettingsFile: Whether this is a camera settings file.
    init(relativeSourcePath: String,
         absoluteSourceRoot: String,
         absoluteDestinationPath: String,
         sha256Hash: String,
         fileSizeBytes: Int64,
         isSettingsFile: Bool = false) {
        self.relativeSourcePath = relativeSourcePath
        self.absoluteSourceRoot = absoluteSourceRoot
        self.absoluteDestinationPath = absoluteDestinationPath
        self.sha256Hash = sha256Hash
        self.fileSizeBytes = fileSizeBytes
        self.verifiedDate = Date()
        self.isSettingsFile = isSettingsFile
    }
}
