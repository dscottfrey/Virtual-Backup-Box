// FolderPickerView.swift
// Virtual Backup Box
//
// UIViewControllerRepresentable wrapper around UIDocumentPickerViewController
// for folder selection. The picker is configured to land at the Files app's
// Browse/Locations root every time it opens, so the user can see connected
// drives, cards, iCloud Drive, and on-device storage as siblings — no
// "Recents" detour, no being buried deep in iCloud after an alternating
// source/destination pick.
//
// How the Browse/Locations landing is achieved: directoryURL is set to a
// deliberately non-resolving path. UIDocumentPicker can't navigate there,
// so it falls back to the Browse view at the top of the navigation stack.
// This is undocumented behavior — Apple could change it in a future iOS
// release — but it has been the most reliable way found to escape the
// "open where you last picked" default and is in production today.
//
// What we tried before and why this is the layout now:
// An earlier two-layer strategy resolved a saved last-pick bookmark as
// the primary path and only fell back to the non-resolving URL on first
// run or card-ejected cases. The problem (Scott 2026-05-13): the user
// alternates source and destination picks. After picking a destination
// deep inside iCloud Drive, the next source pick reopened in that same
// iCloud subfolder — exactly where the camera card is NOT. Forcing the
// picker to root every time is the user's clearly stated preference even
// though it means an extra scroll-tap on each pick.
//
// What we still save (but don't read) for bookmarks:
// saveBookmark(for:) is still called from the coordinator after every
// successful pick. The data sits unused in UserDefaults — preserved so a
// future "smart starting location" feature can revive last-pick or
// quick-select without needing to re-grant permissions. clearBookmark()
// is kept for the same reason. If those become genuinely dead, delete
// them then; today they cost nothing.
//
// A previous "Layer 0" tried to pre-navigate the picker to a mounted
// card's volume root from MountedVolumeService. That service is now
// bookmark-based and the "Choose Previous" path skipped the picker
// entirely (now also removed from UI, 2026-05-13). Layer 0 was dropped
// 2026-05-12 as dead code.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FolderPickerView: UIViewControllerRepresentable {

    /// UserDefaults key for the saved source folder bookmark.
    private static let bookmarkKey = "lastSourceFolderBookmark"

    /// Called with the selected folder URL when the user confirms.
    let onPicked: (URL) -> Void

    /// Called when the user cancels the picker.
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancelled: onCancelled)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder]
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false

        // Always force Browse/Locations root via a non-resolving directoryURL.
        // The UUID suffix guarantees a path UIDocumentPicker has no chance of
        // resolving, which triggers the fallback to the Browse navigation
        // root. See the file header for the full rationale and history.
        let startURL = URL(
            fileURLWithPath: "/private/var/_force_browse_\(UUID().uuidString)"
        )
        picker.directoryURL = startURL

        DebugLogService.shared.log(
            "[FolderPicker] directoryURL forced to non-resolving path: \(startURL.path)"
        )
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    // MARK: - Bookmark Management
    //
    // Bookmarks are still saved on every successful pick so a future
    // smart-starting-location feature can revive them without re-prompting
    // for permission. They are NOT read to position the picker today —
    // the picker always opens at Browse/Locations root (see makeUIViewController).

    /// Saves a security-scoped bookmark for the given URL. Currently used
    /// only as future-proofing — the data is preserved in UserDefaults so
    /// quick-select or last-pick-restoration can be added later without
    /// having to re-request permission from the user.
    static func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            DebugLogService.shared.log("[FolderPicker] Saved bookmark for: \(url.path)")
        } catch {
            DebugLogService.shared.log("[FolderPicker] Failed to save bookmark: \(error)")
        }
    }

    /// Clears the saved source bookmark. Called from settings or reset.
    static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        let onCancelled: () -> Void

        init(onPicked: @escaping (URL) -> Void,
             onCancelled: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancelled = onCancelled
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else { return }

            // Save the bookmark even though we no longer read it to position
            // the next picker — see file header. Future-proofing for a
            // possible quick-select revival.
            FolderPickerView.saveBookmark(for: url)

            onPicked(url)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            onCancelled()
        }
    }
}
