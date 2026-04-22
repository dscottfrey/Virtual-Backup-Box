// SelectionViewModel+Targets.swift
// Virtual Backup Box
//
// Extension on SelectionViewModel that handles all target (backup destination)
// management: resolving bookmarks on launch, adding new targets, selecting,
// renaming, and removing targets. Split from the main ViewModel file to
// respect the ~200-line-per-file rule (§6.3).

import Foundation
import SwiftData

extension SelectionViewModel {

    // MARK: - Target Resolution

    /// Fetches all KnownTargets from the database, resolves each bookmark to
    /// check availability, and sets the first available one as the active
    /// target. Called on app launch and after any target is added or removed.
    func resolveKnownTargets() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<KnownTarget>(
            sortBy: [SortDescriptor(\.lastUsedDate, order: .reverse)]
        )
        allTargets = (try? context.fetch(descriptor)) ?? []

        // Release any currently held target access
        activeTargetURL?.stopAccessingSecurityScopedResource()
        activeTarget = nil
        activeTargetURL = nil
        availableSpaceBytes = nil
        targetAvailability = [:]

        for target in allTargets {
            guard let resolved = BookmarkService.resolveBookmark(
                target.bookmarkData
            ) else {
                targetAvailability[ObjectIdentifier(target)] = false
                continue
            }

            let url = resolved.url
            let granted = url.startAccessingSecurityScopedResource()
            let readable = granted && FileManager.default.isReadableFile(
                atPath: url.path
            )
            targetAvailability[ObjectIdentifier(target)] = readable

            if readable && activeTarget == nil {
                // First available target — keep access open
                activeTarget = target
                activeTargetURL = url
                availableSpaceBytes = BookmarkService.availableSpace(at: url)
            } else if granted {
                // Not using this one — release access
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    /// Switches the active target to a different known target.
    /// Stops access on the previous target and starts it on the new one.
    func selectTarget(_ target: KnownTarget) {
        activeTargetURL?.stopAccessingSecurityScopedResource()
        activeTarget = nil
        activeTargetURL = nil
        availableSpaceBytes = nil

        guard let resolved = BookmarkService.resolveBookmark(
            target.bookmarkData
        ) else { return }

        let url = resolved.url
        guard url.startAccessingSecurityScopedResource() else { return }

        activeTarget = target
        activeTargetURL = url
        availableSpaceBytes = BookmarkService.availableSpace(at: url)
    }

    // MARK: - Adding a Target

    /// Handles a URL selected from the document picker for a new target.
    ///
    /// Creates the security-scoped bookmark immediately (while access is
    /// active from the picker) and stores it for the user to confirm with
    /// a friendly name. Returns true if the bookmark was created, false if
    /// access or bookmark creation failed.
    func handleTargetSelected(url: URL) -> Bool {
        let granted = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        guard granted else { return false }

        guard let bookmarkData = try? BookmarkService.createBookmark(
            for: url
        ) else { return false }

        pendingBookmarkData = bookmarkData
        pendingTargetName = BookmarkService.volumeName(at: url)
            ?? url.lastPathComponent
        return true
    }

    /// Saves the pending target with the user-confirmed friendly name.
    /// Called after the user enters a name in the naming alert.
    func confirmTargetName(_ name: String) {
        guard let context = modelContext,
              let bookmarkData = pendingBookmarkData else { return }

        let target = KnownTarget(
            friendlyName: name,
            bookmarkData: bookmarkData
        )
        context.insert(target)
        pendingBookmarkData = nil
        resolveKnownTargets()
    }

    // MARK: - Removing and Renaming

    /// Deletes a known target from the database. If it was the active target,
    /// releases its security-scoped access and clears the active target state.
    func removeTarget(_ target: KnownTarget) {
        guard let context = modelContext else { return }

        if activeTarget === target {
            activeTargetURL?.stopAccessingSecurityScopedResource()
            activeTarget = nil
            activeTargetURL = nil
            availableSpaceBytes = nil
        }

        context.delete(target)
        resolveKnownTargets()
    }

    /// Updates a target's display name. Does not affect the bookmark or any
    /// stored paths — the name is purely for the user's convenience.
    func renameTarget(_ target: KnownTarget, to newName: String) {
        target.friendlyName = newName
    }

    // MARK: - Local Internal Storage Target

    /// Whether an "VBB Internal Storage" target already exists in the database.
    var hasInternalStorageTarget: Bool {
        allTargets.contains { $0.friendlyName == "VBB Internal Storage" }
    }

    /// Creates a "Backups" folder inside the app's Documents directory and
    /// registers it as a known target named "VBB Internal Storage". This gives the
    /// user a built-in internal storage option without needing to navigate
    /// the file system via the document picker.
    func addInternalStorageTarget() {
        guard let context = modelContext else { return }

        let documentsURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let backupsURL = documentsURL.appendingPathComponent("VBB Internal Storage")

        // Create the folder if it doesn't exist
        try? FileManager.default.createDirectory(
            at: backupsURL,
            withIntermediateDirectories: true
        )

        // Create a bookmark for the folder. The app's own Documents directory
        // doesn't require security-scoped access, but a bookmark still works
        // and keeps the KnownTarget model consistent.
        guard let bookmarkData = try? BookmarkService.createBookmark(
            for: backupsURL
        ) else { return }

        let target = KnownTarget(
            friendlyName: "VBB Internal Storage",
            bookmarkData: bookmarkData
        )
        context.insert(target)
        resolveKnownTargets()
    }
}
