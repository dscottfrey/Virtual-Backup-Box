// SelectionViewModel.swift
// Virtual Backup Box
//
// Orchestrates the Module 1 selection flow: source folder selection (with
// camera card detection) and the "ready to back up" state check. All
// business logic for the selection screen lives in this ViewModel and its
// target management extension (SelectionViewModel+Targets.swift).
//
// Views bind to this ViewModel's properties but contain no logic themselves.
//
// Uses @Observable (iOS 17+) so SwiftUI views automatically track changes.
// Marked @MainActor because all property updates drive UI and must happen
// on the main thread.

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
class SelectionViewModel {

    // MARK: - Dependencies

    /// Set once when the view appears. All SwiftData operations use this.
    var modelContext: ModelContext?

    // MARK: - Source State

    /// The currently selected source folder URL. Nil until the user picks one.
    var sourceURL: URL?

    /// Display name shown in the source zone (card name or folder name).
    var sourceDisplayName = ""

    /// True if the source has a DCIM folder and a readable volume UUID.
    var sourceIsCard = false

    /// The KnownCard record, if the source is a recognised camera card.
    var selectedCard: KnownCard?

    /// True while extracting camera model from card media files.
    var isReadingCard = false

    /// Whether startAccessingSecurityScopedResource was called on the source.
    private var sourceAccessGranted = false

    // MARK: - Card Naming Dialog State

    var showCardNamingDialog = false
    var pendingCardUUID = ""
    var pendingCameraModel = ""
    var suggestedCardName = ""

    // MARK: - Target State (managed by SelectionViewModel+Targets.swift)

    var activeTarget: KnownTarget?
    var activeTargetURL: URL?
    var availableSpaceBytes: Int64?
    var allTargets: [KnownTarget] = []
    var targetAvailability: [ObjectIdentifier: Bool] = [:]
    var pendingBookmarkData: Data?
    var pendingTargetName = ""

    // MARK: - Picker State

    var showingSourcePicker = false

    // MARK: - Internal Storage Archives

    /// Card archive folders found inside VBB Internal Storage. Each is a
    /// backed-up card mirror (e.g. "20260421_EOS R6 Mark III Card-1") that
    /// the user can select as a source for syncing to an external drive.
    /// No picker needed — this is the app's own Documents directory.
    var internalArchives: [(name: String, url: URL)] {
        let storageURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("VBB Internal Storage")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url in
            let isDir = (try? url.resourceValues(
                forKeys: [.isDirectoryKey]
            ))?.isDirectory ?? false
            guard isDir else { return nil }
            return (name: url.lastPathComponent, url: url)
        }.sorted { $0.name > $1.name }
    }

    /// Known camera cards from the database, sorted by most recently backed
    /// up. Shown in the source zone as a reminder of registered cards —
    /// the user still needs the picker for iOS access, but this helps them
    /// know which cards the app recognises.
    var recentKnownCards: [KnownCard] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<KnownCard>(
            sortBy: [SortDescriptor(\.lastBackupDate, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Selects an internal card archive as the source directly — no picker
    /// needed since it is the app's own Documents directory.
    func selectInternalArchive(url: URL, name: String) {
        stopSourceAccess()
        sourceURL = url
        sourceIsCard = false
        selectedCard = nil
        sourceDisplayName = name
    }

    // MARK: - Computed Properties

    /// True when both source and target are selected and accessible.
    var isReady: Bool { sourceURL != nil && activeTargetURL != nil }

    /// True when the active target is below the space warning threshold.
    var showLowSpaceWarning: Bool {
        guard let space = availableSpaceBytes else { return false }
        return space < Constants.minimumWarningSpaceBytes
    }

    /// The folder name created at the target for this session's files.
    var sessionFolderName: String {
        if let card = selectedCard {
            return card.destinationFolderName
        }
        return sourceURL?.lastPathComponent ?? ""
    }

    // MARK: - Setup

    /// Called once when SelectionView appears.
    func setup(context: ModelContext) {
        self.modelContext = context
        resolveKnownTargets()
    }

    // MARK: - Source Selection

    /// Processes a source URL returned by the document picker.
    ///
    /// Starts security-scoped access, checks for DCIM (camera card), reads
    /// the volume UUID, looks up the card in the database, and — if unknown
    /// — extracts the camera model and triggers the naming dialog.
    func handleSourceSelected(url: URL) async {
        stopSourceAccess()
        sourceAccessGranted = url.startAccessingSecurityScopedResource()
        sourceURL = url
        sourceIsCard = false
        selectedCard = nil

        // Not a camera card — treat as generic folder
        guard CardDetectionService.isCameraCard(at: url) else {
            sourceDisplayName = url.lastPathComponent
            return
        }

        // Can't read UUID — fall back to generic folder
        guard let uuid = CardDetectionService.readVolumeUUID(from: url) else {
            sourceDisplayName = url.lastPathComponent
            return
        }

        sourceIsCard = true

        // Known card — show name, skip the naming dialog
        if let knownCard = lookupCard(uuid: uuid) {
            selectedCard = knownCard
            sourceDisplayName = knownCard.friendlyName
            return
        }

        // Unknown card — read camera model, then show naming dialog
        isReadingCard = true
        let model = await CardDetectionService.extractCameraModel(from: url)
        isReadingCard = false

        pendingCardUUID = uuid
        pendingCameraModel = model ?? ""
        suggestedCardName = suggestCardName(cameraModel: model)
        showCardNamingDialog = true
    }

    /// Saves a new KnownCard after the user confirms the naming dialog.
    func confirmCardName(friendlyName: String, cameraModel: String) {
        guard let context = modelContext else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let folderName = "\(dateFormatter.string(from: Date()))_\(friendlyName)"

        let card = KnownCard(
            uuid: pendingCardUUID,
            friendlyName: friendlyName,
            cameraModel: cameraModel,
            destinationFolderName: folderName
        )
        context.insert(card)

        selectedCard = card
        sourceDisplayName = friendlyName
        showCardNamingDialog = false
    }

    /// Releases security-scoped access on the current source URL.
    func stopSourceAccess() {
        if sourceAccessGranted, let url = sourceURL {
            url.stopAccessingSecurityScopedResource()
            sourceAccessGranted = false
        }
    }

    // MARK: - Private Helpers

    /// Looks up a KnownCard by volume UUID.
    private func lookupCard(uuid: String) -> KnownCard? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<KnownCard>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Suggests a friendly name for a new card based on the camera model
    /// and how many cards of that model already exist in the database.
    private func suggestCardName(cameraModel: String?) -> String {
        guard let context = modelContext else { return "Card-1" }

        if let model = cameraModel, !model.isEmpty {
            let descriptor = FetchDescriptor<KnownCard>(
                predicate: #Predicate { $0.cameraModel == model }
            )
            let count = (try? context.fetchCount(descriptor)) ?? 0
            return "\(model) Card-\(count + 1)"
        }

        let allCards = FetchDescriptor<KnownCard>()
        let count = (try? context.fetchCount(allCards)) ?? 0
        return "Card-\(count + 1)"
    }
}
