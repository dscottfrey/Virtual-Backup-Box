// FolderPickerView.swift
// Virtual Backup Box
//
// UIViewControllerRepresentable wrapper around UIDocumentPickerViewController
// for folder selection. Uses a two-layer strategy to control where the
// picker opens:
//
// Layer 1 (primary): After any successful pick, a security-scoped bookmark
// is saved to UserDefaults. On the next present, the bookmark is resolved
// and set as directoryURL — the picker opens right where the user last
// picked. For the camera-card workflow, this means the picker reopens at
// the card's root if it is still connected.
//
// Layer 2 (fallback): If no bookmark exists or it fails to resolve (card
// ejected, app reinstalled), directoryURL is set to a deliberately
// non-resolving path. This causes the picker to fall back to the
// Browse/Locations root where connected drives and cards are visible —
// instead of burying the user inside "On My iPhone."
//
// The non-resolving URL trick (Layer 2) is undocumented behavior. Apple
// could change it in a future iOS release. Layer 1 is the real fix;
// Layer 2 is a cosmetic fallback for first-run and card-ejected cases.

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

        // Layer 1: try to resolve saved bookmark from last successful pick
        let startURL = Self.resolvedBookmarkURL(coordinator: context.coordinator)

        // Layer 2: if no bookmark, use non-resolving path to force
        // Browse/Locations view instead of iOS's "last used" location
            ?? URL(fileURLWithPath: "/private/var/_force_browse_\(UUID().uuidString)")

        picker.directoryURL = startURL

        DebugLogService.shared.log("[FolderPicker] directoryURL set to: \(startURL.path)")
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    // MARK: - Bookmark Management

    /// Resolves the saved bookmark, returning a usable URL if the volume
    /// is still mounted. Refreshes stale bookmarks automatically. Clears
    /// the stored bookmark if resolution fails entirely.
    private static func resolvedBookmarkURL(coordinator: Coordinator) -> URL? {
        guard let data = UserDefaults.standard.data(
            forKey: bookmarkKey
        ) else {
            DebugLogService.shared.log("[FolderPicker] No saved bookmark — using fallback")
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            DebugLogService.shared.log("[FolderPicker] Bookmark failed to resolve — clearing")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }

        // Refresh stale bookmark silently
        if isStale {
            if let refreshed = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                DebugLogService.shared.log("[FolderPicker] Refreshed stale bookmark")
            } else {
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                DebugLogService.shared.log("[FolderPicker] Stale bookmark could not refresh — clearing")
                return nil
            }
        }

        // Check the volume is actually mounted
        guard FileManager.default.fileExists(atPath: url.path) else {
            DebugLogService.shared.log("[FolderPicker] Bookmarked path not mounted — using fallback")
            return nil
        }

        // Start security-scoped access so the picker can open inside
        if url.startAccessingSecurityScopedResource() {
            coordinator.accessedURL = url
        }
        DebugLogService.shared.log("[FolderPicker] Resolved bookmark: \(url.path)")
        return url
    }

    /// Saves a security-scoped bookmark for the given URL so the picker
    /// opens here next time.
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

        /// Tracks a URL we started security-scoped access on for the
        /// picker's directoryURL. Must be stopped when the picker closes.
        var accessedURL: URL?

        init(onPicked: @escaping (URL) -> Void,
             onCancelled: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancelled = onCancelled
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            defer { stopAccess() }
            guard let url = urls.first else { return }

            // Save bookmark so the picker opens here next time
            FolderPickerView.saveBookmark(for: url)

            onPicked(url)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            stopAccess()
            onCancelled()
        }

        private func stopAccess() {
            accessedURL?.stopAccessingSecurityScopedResource()
            accessedURL = nil
        }
    }
}
