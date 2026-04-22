// DestinationPathService.swift
// Virtual Backup Box
//
// Computes file paths for the backup destination. Given a source file URL
// and the source root, it can produce the relative path (for database
// lookup) and the full destination URL (for writing).
//
// The destination layout is:
//   [target root] / [session folder] / [relative path from source root]
//
// This service must never be called from a View.

import Foundation

nonisolated enum DestinationPathService {

    /// Computes the path of a file relative to a root folder.
    ///
    /// Example: if rootURL is "/Volumes/CARD" and fileURL is
    /// "/Volumes/CARD/DCIM/100EOSR6/_MG_1530.CR3", the result
    /// is "DCIM/100EOSR6/_MG_1530.CR3".
    ///
    /// Root-level files (e.g. .CSD settings files) return just their
    /// filename with no leading slash.
    static func relativePath(of fileURL: URL, relativeTo rootURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return relative
    }

    /// Computes the full destination URL for a file given its relative path.
    ///
    /// The destination is: targetRoot / sessionFolderName / relativePath.
    /// This creates URLs like:
    ///   /Volumes/T7/20260421_EOS R6 Mark III Card-1/DCIM/100EOSR6/_MG_1530.CR3
    static func destinationURL(
        relativePath: String,
        targetRoot: URL,
        sessionFolderName: String
    ) -> URL {
        targetRoot
            .appendingPathComponent(sessionFolderName)
            .appendingPathComponent(relativePath)
    }
}
