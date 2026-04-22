// SourceFile.swift
// Virtual Backup Box
//
// Represents a single file discovered during the Module 2 source scan.
// Each file is categorised as either .copy (needs to be backed up) or
// .skip (already has a verified copy at the destination). This struct
// is not a SwiftData model — it exists only in memory during a session.

import Foundation

/// Whether a scanned file needs to be copied or can be skipped.
enum FileStatus: Sendable {
    /// File needs to be copied and verified.
    case copy
    /// File already has a verified copy at the destination — skip it.
    case skip
}

/// One file from the source, with all the metadata needed by Module 3
/// (Copy Engine) and Module 4 (Verification) to process it.
struct SourceFile: Sendable {

    /// Full URL of the source file.
    let url: URL

    /// Path relative to the source root (e.g. "DCIM/100EOSR6/_MG_1530.CR3").
    /// Used as the database lookup key and for constructing destination paths.
    let relativePath: String

    /// File size in bytes, from filesystem metadata.
    let fileSizeBytes: Int64

    /// Whether this file needs to be copied or is already backed up.
    let status: FileStatus

    /// True if this file matches the camera settings file pattern for the
    /// detected camera model (e.g. .CSD at root for Canon). Used by the
    /// settings restore stretch goal (§9.1).
    let isSettingsFile: Bool

    /// Pre-computed full destination URL where this file will be written.
    /// Computed by DestinationPathService during the scan so Module 3
    /// doesn't need to recompute it.
    let destinationURL: URL
}
