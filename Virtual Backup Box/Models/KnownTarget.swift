// KnownTarget.swift
// Virtual Backup Box
//
// Represents a known backup destination folder, persisted so the app can
// reconnect to it automatically across sessions without requiring the user
// to re-select it from the document picker each time.
//
// Persistence works via a security-scoped bookmark — a Data blob that iOS can
// resolve back to a URL even after the app restarts, as long as the volume is
// still accessible. See BookmarkService (Module 1) for how to create and
// resolve these bookmarks.
//
// Whether the target is currently available (drive plugged in, iCloud reachable)
// is determined at runtime by attempting to resolve the bookmark. This status is
// never stored in the database — storing it would create stale data that
// disagrees with reality.

import Foundation
import SwiftData

@Model
final class KnownTarget {

    // MARK: - Stored Properties

    /// User-assigned display name for this destination.
    /// Examples: "Samsung T7", "Vacation Drive", "iCloud Drive"
    /// Set by the user when the target is first added; can be renamed later.
    var friendlyName: String

    /// Security-scoped bookmark data for the target folder URL.
    /// Created by BookmarkService when the target is first added via the
    /// system document picker. Resolved by BookmarkService at the start of
    /// each session to obtain a usable URL.
    ///
    /// If resolution fails (drive reformatted, renamed, or not plugged in),
    /// the target is shown as "unavailable" in the UI — never silently removed.
    var bookmarkData: Data

    /// When this target was first added to the app.
    var addedDate: Date

    /// When this target was last used as the destination for a completed
    /// backup session. Nil if the target has been added but never used.
    var lastUsedDate: Date?

    // MARK: - Initialiser

    /// Creates a new KnownTarget record.
    ///
    /// Called by Module 1 when the user selects a new destination folder
    /// via the system document picker and confirms a friendly name.
    ///
    /// - Parameters:
    ///   - friendlyName: The user-chosen display name for this target.
    ///   - bookmarkData: Security-scoped bookmark data for the selected URL.
    init(friendlyName: String, bookmarkData: Data) {
        self.friendlyName = friendlyName
        self.bookmarkData = bookmarkData
        self.addedDate = Date()
        self.lastUsedDate = nil
    }
}
