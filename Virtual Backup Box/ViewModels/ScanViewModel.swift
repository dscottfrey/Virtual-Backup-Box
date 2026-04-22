// ScanViewModel.swift
// Virtual Backup Box
//
// Orchestrates the Module 2 source scan. Fetches verified records from
// SwiftData (on the main actor, where ModelContext lives), then runs the
// scan off the main thread via Task.detached, posting progress updates
// back to the UI as files are enumerated.
//
// This ViewModel is created by SelectionView when "Start Backup" is tapped
// and owns the scan lifecycle. The resulting ScanResult is passed forward
// to Module 3 when the user confirms.

import Foundation
import SwiftData
import Observation

@Observable
class ScanViewModel {

    // MARK: - Configuration (set at init, never changed)

    let sourceURL: URL
    let targetURL: URL
    let sessionFolderName: String
    let cameraModel: String?
    let selectedCard: KnownCard?
    private let modelContext: ModelContext

    // MARK: - Scan State

    /// True while the scan is running.
    var isScanning = false

    /// Running count of files found during enumeration.
    var filesFound = 0

    /// The completed scan result. Nil until the scan finishes.
    var scanResult: ScanResult?

    /// Available space on the target, checked at scan start.
    var availableSpaceBytes: Int64?

    // MARK: - Init

    /// Creates a ScanViewModel with all the context needed to run a scan.
    init(sourceURL: URL,
         targetURL: URL,
         sessionFolderName: String,
         cameraModel: String?,
         selectedCard: KnownCard?,
         modelContext: ModelContext) {
        self.sourceURL = sourceURL
        self.targetURL = targetURL
        self.sessionFolderName = sessionFolderName
        self.cameraModel = cameraModel
        self.selectedCard = selectedCard
        self.modelContext = modelContext
    }

    // MARK: - Scan Execution

    /// Starts the scan. Fetches DB records on the main actor, then runs
    /// file enumeration and comparison off the main thread.
    func startScan() async {
        isScanning = true
        availableSpaceBytes = BookmarkService.availableSpace(at: targetURL)

        // Fetch verified records on main actor (ModelContext requires it)
        let records = fetchVerifiedRecords()

        // Capture values for the detached task (must be Sendable)
        let source = sourceURL
        let target = targetURL
        let folder = sessionFolderName
        let camera = cameraModel

        // Run the scan off the main thread
        let result = await Task.detached {
            SourceScannerService.performScan(
                sourceURL: source,
                targetURL: target,
                sessionFolderName: folder,
                cameraModel: camera,
                verifiedRecords: records,
                onProgress: { count in
                    Task { @MainActor [weak self] in
                        self?.filesFound = count
                    }
                }
            )
        }.value

        scanResult = result
        isScanning = false
    }

    // MARK: - Database Query

    /// Fetches all verified FileRecords for this destination and returns
    /// them as a dictionary keyed by relative source path.
    ///
    /// Matches by destination path prefix (target + session folder) rather
    /// than source root, because iOS assigns different mount paths to
    /// removable media each time they are connected. The destination path
    /// is stable: it comes from the bookmarked target URL and the card's
    /// fixed destinationFolderName.
    ///
    /// This is a single batch fetch — not per-file queries — as required
    /// by the spec for scan performance.
    private func fetchVerifiedRecords() -> [String: VerifiedFileInfo] {
        let destPrefix = targetURL
            .appendingPathComponent(sessionFolderName).path

        // Fetch all FileRecords — we filter in memory by destination prefix
        // because #Predicate does not support hasPrefix/contains on strings.
        let descriptor = FetchDescriptor<FileRecord>()
        let allRecords = (try? modelContext.fetch(descriptor)) ?? []

        var map: [String: VerifiedFileInfo] = [:]
        for record in allRecords {
            if record.absoluteDestinationPath.hasPrefix(destPrefix) {
                map[record.relativeSourcePath] = VerifiedFileInfo(
                    fileSizeBytes: record.fileSizeBytes,
                    absoluteDestinationPath: record.absoluteDestinationPath
                )
            }
        }
        return map
    }
}
