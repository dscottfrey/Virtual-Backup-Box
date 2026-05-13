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

    /// Fetches all KnownTargets, resolves each bookmark, and sets the
    /// first available one as the active target. Called on launch and
    /// after any target is added or removed. Kept as a sync entry point
    /// — internally spawns a Task and runs each bookmark resolution off
    /// the main thread so the UI stays responsive while iOS wakes the
    /// per-volume UserFS file provider.
    ///
    /// Why this is async-internally instead of blocking:
    /// URL(resolvingBookmarkData:) waits for the file provider IPC to
    /// answer. On a freshly-plugged USB drive that wait can be several
    /// seconds. Resolving N targets sequentially on the main thread
    /// froze the Manage Destinations sheet — rows stayed gray with no
    /// indication anything was happening (Scott 2026-05-13: "took quite
    /// a while to turn green, we should have a warning that there is a
    /// delay"). Moving the per-target resolveBookmark call into a
    /// detached task lets SwiftUI render the "Checking availability…"
    /// state from isResolvingTargets, and the rows update one-by-one as
    /// each resolution completes.
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

        // Snapshot the targets and their bookmark data — KnownTarget is
        // a SwiftData model and only safe to read on the main actor.
        // bookmarkData is plain Data and crosses to the detached task
        // without trouble.
        let snapshot: [(target: KnownTarget, bookmarkData: Data)] =
            allTargets.map { ($0, $0.bookmarkData) }

        isResolvingTargets = true
        Task { @MainActor in
            defer { isResolvingTargets = false }

            for entry in snapshot {
                // Bookmark resolution can block for seconds waiting on
                // the file provider. Detached so it doesn't freeze main.
                let resolved = await Task.detached {
                    BookmarkService.resolveBookmark(entry.bookmarkData)
                }.value

                guard let resolved else {
                    targetAvailability[ObjectIdentifier(entry.target)] = false
                    continue
                }

                let url = resolved.url
                let granted = url.startAccessingSecurityScopedResource()
                let readable = granted && FileManager.default.isReadableFile(
                    atPath: url.path
                )
                targetAvailability[ObjectIdentifier(entry.target)] = readable

                if readable && activeTarget == nil {
                    // First available target — keep access open
                    activeTarget = entry.target
                    activeTargetURL = url
                    availableSpaceBytes = BookmarkService.availableSpace(
                        at: url
                    )
                } else if granted {
                    // Not using this one — release access
                    url.stopAccessingSecurityScopedResource()
                }

                // Yield between targets so SwiftUI repaints the per-row
                // dots and the "Checking availability…" footer doesn't
                // appear to all-update-at-once at the very end.
                await Task.yield()
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

    /// The outcome of a fileImporter pick for a backup destination.
    /// Lets the view choose between showing the naming alert (a real
    /// new target), silently activating an existing target (the picked
    /// URL matches a known one — no duplicate created), or doing nothing
    /// on a failure to access or bookmark the URL.
    enum TargetPickResult {
        case new
        case existing(KnownTarget)
        case failed
    }

    /// Handles a URL selected from the document picker for a new target.
    ///
    /// Before treating the URL as a brand-new target, every known
    /// target's bookmark is resolved and compared by file path. If a
    /// match is found the existing target is activated and no new
    /// KnownTarget is created — fixes the duplicate-on-re-pick problem
    /// Scott surfaced 2026-05-13 (couldn't tap the gray flash-drive row
    /// in Manage Destinations, fell back to Add External, ended up with
    /// two entries for the same drive).
    ///
    /// Otherwise creates the security-scoped bookmark immediately (while
    /// access from the picker is still live) and stores it on the
    /// pending-bookmark state for the user to confirm with a name.
    func handleTargetSelected(url: URL) -> TargetPickResult {
        let granted = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        guard granted else { return .failed }

        // Dedup: does any known target already resolve to this path?
        if let existing = findKnownTarget(matchingPath: url.path) {
            selectTarget(existing)
            return .existing(existing)
        }

        guard let bookmarkData = try? BookmarkService.createBookmark(
            for: url
        ) else { return .failed }

        pendingBookmarkData = bookmarkData
        pendingTargetName = BookmarkService.volumeName(at: url)
            ?? url.lastPathComponent
        return .new
    }

    /// Resolves every known target and returns the first whose bookmarked
    /// URL matches the given file path. Used by handleTargetSelected to
    /// avoid creating duplicate KnownTargets when the user re-picks a
    /// drive that is already saved.
    ///
    /// Note on path equality: we compare on URL.path strings rather than
    /// URL equality. Two URLs to the same file can differ in trailing
    /// slash, file-reference vs path style, etc. The string path
    /// normalisation is good enough for the "is this the same volume
    /// folder?" question we are actually answering here.
    private func findKnownTarget(matchingPath path: String) -> KnownTarget? {
        for target in allTargets {
            guard let resolved = BookmarkService.resolveBookmark(
                target.bookmarkData
            ) else { continue }

            let started = resolved.url.startAccessingSecurityScopedResource()
            defer {
                if started {
                    resolved.url.stopAccessingSecurityScopedResource()
                }
            }

            if resolved.url.path == path {
                return target
            }
        }
        return nil
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
