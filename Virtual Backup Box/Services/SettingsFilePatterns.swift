// SettingsFilePatterns.swift
// Virtual Backup Box
//
// Lookup table that maps camera model strings to the file patterns that
// identify camera settings files. The scanner consults this table during
// enumeration; it does not contain camera-specific logic itself.
//
// Settings file tagging supports the stretch goal (§9.1 — Camera Settings
// Restore to Card). If no pattern exists for a given camera model, files
// are simply not tagged — the stretch goal won't have settings to restore
// for that camera until a pattern is added here.
//
// To add a new camera: add one entry to the `patterns` dictionary.

import Foundation

/// Describes which files on a camera card are settings files.
struct SettingsFilePattern: Sendable {

    /// File extensions that identify settings files (uppercase, no dot).
    let extensions: Set<String>

    /// If true, only files at the source root level match. Files with
    /// these extensions inside subfolders are not considered settings files.
    let mustBeAtSourceRoot: Bool
}

nonisolated enum SettingsFilePatterns {

    /// Camera model string → settings file pattern.
    /// Add new cameras here as they are encountered and tested.
    static let patterns: [String: SettingsFilePattern] = [
        "Canon EOS R6 Mark III": SettingsFilePattern(
            extensions: ["CSD"],
            mustBeAtSourceRoot: true
        )
    ]

    /// Checks whether a file at the given relative path is a settings file
    /// for the specified camera model.
    ///
    /// - Parameters:
    ///   - relativePath: The file's path relative to the source root
    ///     (e.g. "CDEFAULT.CSD" for a root-level file, or "DCIM/file.CSD"
    ///     for a file inside a subfolder).
    ///   - cameraModel: The camera model string (e.g. "Canon EOS R6 Mark III").
    ///     If nil or unknown, returns false.
    static func isSettingsFile(
        relativePath: String,
        cameraModel: String?
    ) -> Bool {
        guard let model = cameraModel,
              let pattern = patterns[model] else {
            return false
        }

        let ext = (relativePath as NSString).pathExtension.uppercased()
        guard pattern.extensions.contains(ext) else { return false }

        if pattern.mustBeAtSourceRoot {
            // Root-level files have no "/" in their relative path
            return !relativePath.contains("/")
        }

        return true
    }
}
