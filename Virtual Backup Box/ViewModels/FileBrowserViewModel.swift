// FileBrowserViewModel.swift
// Virtual Backup Box
//
// Manages state for the file browser: card mirror list, selected card,
// current tab (images/videos), file lists, and multi-select mode.
// Coordinates with FileBrowserService for data and ThumbnailService
// for image loading. Contains no UI logic.

import Foundation
import SwiftData
import Observation

@Observable
class FileBrowserViewModel {

    var modelContext: ModelContext?

    // MARK: - Card List

    var cardMirrors: [CardMirror] = []
    var selectedMirror: CardMirror?

    // MARK: - Media Tab

    enum MediaTab { case images, videos }
    var currentTab: MediaTab = .images

    // MARK: - File Lists

    var imageFiles: [MediaFile] = []
    var videoFiles: [MediaFile] = []

    var currentFiles: [MediaFile] {
        currentTab == .images ? imageFiles : videoFiles
    }

    // MARK: - Selection

    var isSelecting = false
    var selectedURLs: Set<URL> = []

    var selectedCount: Int { selectedURLs.count }

    // MARK: - Delete / Share

    var showDeleteConfirmation = false
    var showShareSheet = false

    // MARK: - Setup

    func setup(context: ModelContext) {
        self.modelContext = context
        loadCardMirrors()
    }

    func loadCardMirrors() {
        guard let context = modelContext else { return }
        cardMirrors = FileBrowserService.findCardMirrors(context: context)
    }

    // MARK: - Card Selection

    func selectCard(_ mirror: CardMirror) {
        selectedMirror = mirror
        imageFiles = FileBrowserService.imageFiles(in: mirror.folderURL)
        videoFiles = FileBrowserService.videoFiles(in: mirror.folderURL)
        currentTab = .images
        clearSelection()
    }

    // MARK: - Multi-Select

    func toggleSelection(_ file: MediaFile) {
        if selectedURLs.contains(file.url) {
            selectedURLs.remove(file.url)
        } else {
            selectedURLs.insert(file.url)
        }
    }

    func selectAll() {
        selectedURLs = Set(currentFiles.map(\.url))
    }

    func clearSelection() {
        isSelecting = false
        selectedURLs = []
    }

    var selectedFileURLs: [URL] {
        currentFiles.filter { selectedURLs.contains($0.url) }.map(\.url)
    }

    /// Names of selected files for the delete confirmation (up to 5).
    var deleteConfirmationMessage: String {
        let files = currentFiles.filter { selectedURLs.contains($0.url) }
        if files.count <= 5 {
            let names = files.map(\.fileName).joined(separator: "\n")
            return "Delete these files? This cannot be undone.\n\n\(names)"
        }
        return "Delete \(files.count) files? This cannot be undone."
    }

    // MARK: - Deletion

    /// Deletes the selected files from disk and removes them from the list.
    /// Does NOT update any database records — FileRecords for external
    /// targets remain valid after internal storage deletion.
    func deleteSelectedFiles() {
        for url in selectedURLs {
            // DELIBERATE EXCEPTION to read-only source rule (§2 of overall
            // directive). Files being deleted here are on internal local storage
            // (staging area only). Verified copies exist on external targets
            // per FileRecord entries in the database. Deletion is triggered
            // only by explicit user confirmation.
            try? FileManager.default.removeItem(at: url)
        }

        imageFiles.removeAll { selectedURLs.contains($0.url) }
        videoFiles.removeAll { selectedURLs.contains($0.url) }
        clearSelection()
    }

    /// Deletes a single file (from full-screen viewer trash button).
    func deleteSingleFile(_ file: MediaFile) {
        // DELIBERATE EXCEPTION to read-only source rule (§2 of overall
        // directive). See deleteSelectedFiles() for rationale.
        try? FileManager.default.removeItem(at: file.url)
        imageFiles.removeAll { $0.url == file.url }
        videoFiles.removeAll { $0.url == file.url }
    }
}
