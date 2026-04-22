// DebugLogService.swift
// Virtual Backup Box
//
// File-based debug logger that writes timestamped entries to an iCloud
// Drive folder. Needed because the USB-C port is occupied by the card
// reader during testing — Xcode console is unavailable.
//
// The log folder location is selected by the user once (via document
// picker) and stored as a security-scoped bookmark in UserDefaults.
// If no location is set, log calls are silently skipped.
//
// Logs are appended to "VBB_Debug_Log.txt" in the selected folder.
// The file can be read on a Mac via iCloud Drive sync.

import Foundation

final class DebugLogService: @unchecked Sendable {

    static let shared = DebugLogService()

    private static let bookmarkKey = "debugLogFolderBookmark"
    private var logFileURL: URL?
    private var accessedURL: URL?
    private let queue = DispatchQueue(label: "com.vbb.debuglog")

    private init() {
        resolveLogFolder()
    }

    // MARK: - Public API

    /// Whether a log location has been configured.
    var isConfigured: Bool { logFileURL != nil }

    /// Writes a timestamped log entry. Thread-safe. Silently skips if
    /// no log location is configured.
    func log(_ message: String, file: String = #file, function: String = #function) {
        guard let logURL = logFileURL else { return }
        let fileName = (file as NSString).lastPathComponent
        let timestamp = Self.formatter.string(from: Date())
        let entry = "[\(timestamp)] [\(fileName):\(function)] \(message)\n"

        queue.async {
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logURL)
                }
            }
        }
    }

    // MARK: - Folder Management

    /// Saves a bookmark for the selected log folder. Called after the user
    /// picks a folder via the document picker.
    func setLogFolder(url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        resolveLogFolder()
        log("Debug logging started")
    }

    /// Clears the saved log folder bookmark.
    func clearLogFolder() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        logFileURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    // MARK: - Private

    /// Resolves the saved bookmark and sets up the log file URL.
    private func resolveLogFolder() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        logFileURL = nil

        guard let data = UserDefaults.standard.data(
            forKey: Self.bookmarkKey
        ) else { return }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            return
        }

        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }

        logFileURL = url.appendingPathComponent("VBB_Debug_Log.txt")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}
