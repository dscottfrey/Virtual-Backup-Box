// BookmarkService.swift
// Virtual Backup Box
//
// Creates, resolves, and manages security-scoped bookmarks for persistent
// access to user-selected folders (backup targets). Security-scoped bookmarks
// allow the app to re-access a folder across launches without requiring the
// user to re-select it from the document picker.
//
// Also provides helpers for reading volume metadata (available space, volume
// name) since these are always needed in the context of target management.
//
// iOS requires startAccessingSecurityScopedResource() before any file
// operations on a bookmarked URL, and stopAccessingSecurityScopedResource()
// when done. Forgetting to stop is a resource leak. Always use defer.

import Foundation

nonisolated enum BookmarkService {

    /// Creates a security-scoped bookmark for the given URL.
    ///
    /// The URL must be a security-scoped URL returned by the system document
    /// picker, with startAccessingSecurityScopedResource() already called.
    /// Returns the bookmark as Data, suitable for storing in a KnownTarget.
    static func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves stored bookmark data back to a usable URL.
    ///
    /// Returns the resolved URL and whether the bookmark is stale. A stale
    /// bookmark still works but should be recreated. Returns nil if the
    /// bookmark cannot be resolved at all (volume gone, reformatted, etc.).
    static func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return (url, isStale)
    }

    /// Reads the available storage space on the volume containing the URL.
    ///
    /// Uses volumeAvailableCapacityForImportantUsageKey, which Apple
    /// recommends for user-initiated data. Returns nil if the value cannot
    /// be determined.
    static func availableSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Reads the volume display name for the given URL.
    ///
    /// Used to pre-fill the friendly name field when adding a new target.
    /// Returns nil if the volume name cannot be read.
    static func volumeName(at url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName
    }
}
