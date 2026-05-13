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

    /// True while resolveKnownTargets is iterating bookmarks. Drives the
    /// "Checking availability…" footer in ManageTargetsView so the user
    /// understands why rows might appear gray for a second or two after
    /// the sheet opens — iOS's UserFS file provider needs to wake before
    /// bookmarks resolve and reachability turns true. Added 2026-05-13
    /// after Scott reported that the flash drive row "took quite a
    /// while to turn green" with no on-screen explanation.
    var isResolvingTargets = false

    // MARK: - Picker State

    var showingSourcePicker = false

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

        // Known card — show name, skip the naming dialog. Refresh the
        // per-card bookmark so the next session can detect the card as
        // mounted and skip the picker entirely. We do this on every
        // successful pick (not just first-pick) because bookmarks can
        // go stale and re-picking is the moment we have a guaranteed
        // valid one.
        if let knownCard = lookupCard(uuid: uuid) {
            selectedCard = knownCard
            sourceDisplayName = knownCard.friendlyName
            saveBookmark(for: url, on: knownCard)
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
    /// Diagnostic logs around each step are intentional: a freeze was
    /// reported on Confirm with the button stuck white. The logs let us
    /// see in the iCloud debug log exactly which step (if any) hangs.
    func confirmCardName(friendlyName: String, cameraModel: String) {
        DebugLogService.shared.log("[ConfirmCard] enter — name=\(friendlyName) model=\(cameraModel)")

        guard let context = modelContext else {
            DebugLogService.shared.log("[ConfirmCard] no modelContext — bailing")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let folderName = "\(dateFormatter.string(from: Date()))_\(friendlyName)"

        let card = KnownCard(
            uuid: pendingCardUUID,
            friendlyName: friendlyName,
            cameraModel: cameraModel,
            destinationFolderName: folderName
        )
        DebugLogService.shared.log("[ConfirmCard] about to insert card uuid=\(pendingCardUUID)")
        context.insert(card)
        DebugLogService.shared.log("[ConfirmCard] inserted; setting selectedCard")

        // Capture the per-card bookmark now, while the user-granted
        // security-scoped access from handleSourceSelected is still live.
        // This is what powers one-tap re-selection from the source zone
        // on every subsequent insertion of this card.
        if let url = sourceURL {
            saveBookmark(for: url, on: card)
        }

        selectedCard = card
        DebugLogService.shared.log("[ConfirmCard] selectedCard set; setting sourceDisplayName")
        sourceDisplayName = friendlyName
        DebugLogService.shared.log("[ConfirmCard] sourceDisplayName set; closing dialog")
        showCardNamingDialog = false
        DebugLogService.shared.log("[ConfirmCard] exit")
    }

    /// Releases security-scoped access on the current source URL.
    func stopSourceAccess() {
        if sourceAccessGranted, let url = sourceURL {
            url.stopAccessingSecurityScopedResource()
            sourceAccessGranted = false
        }
    }

    /// Confirms the currently-selected source still points at a reachable
    /// volume AND, if it's a known card, that the volume UUID at the URL
    /// still matches the selected card. Clears the source and returns
    /// false otherwise. Safe to call when no source is selected.
    ///
    /// Why this matters — the card-swap scenario:
    /// Scott reported (2026-05-12) that after picking a known card via
    /// Select Previous, pulling the reader and inserting a different
    /// card, the app continued to treat the old card as the active
    /// source. The mount path embeds the volume UUID so the bookmark
    /// for Card-A no longer resolves after Card-A is unplugged; but the
    /// viewModel still holds Card-A's sourceURL/selectedCard. If files
    /// existed on Card-B and the user tapped Verify in that state, the
    /// scan would have attributed Card-B's files to Card-A's
    /// destination folder — data integrity bug. This guard runs on
    /// every mount-refresh and at scan start to make that impossible.
    @discardableResult
    func validateSourceStillValid() -> Bool {
        guard let url = sourceURL else { return true }

        let reachable = (try? url.checkResourceIsReachable()) ?? false
        if !reachable {
            DebugLogService.shared.log(
                "[ValidateSource] sourceURL no longer reachable — clearing"
            )
            clearSource()
            return false
        }

        if let card = selectedCard {
            let currentUUID = CardDetectionService.readVolumeUUID(from: url)
            if let uuid = currentUUID, uuid != card.uuid {
                DebugLogService.shared.log(
                    "[ValidateSource] UUID at sourceURL changed (\(card.uuid) → \(uuid)) — card was swapped, clearing"
                )
                clearSource()
                return false
            }
        }

        return true
    }

    /// Resets all source-related state. Used when validation finds the
    /// source has gone away (card unplugged or swapped underneath us).
    private func clearSource() {
        stopSourceAccess()
        sourceURL = nil
        sourceDisplayName = ""
        sourceIsCard = false
        selectedCard = nil
    }

    // MARK: - Private Helpers

    /// Captures a security-scoped bookmark for the picked URL and saves it
    /// onto the KnownCard. Used to power "Choose Previous" — on the next
    /// app launch, resolving this bookmark tells us whether the card is
    /// mounted AND gives us sandbox access without re-presenting the
    /// picker. Failures are logged but non-fatal: the card still works as
    /// a source via the normal picker.
    private func saveBookmark(for url: URL, on card: KnownCard) {
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            card.bookmarkData = data
            DebugLogService.shared.log(
                "[KnownCardBookmark] saved bookmark for \(card.friendlyName)"
            )
        } catch {
            DebugLogService.shared.log(
                "[KnownCardBookmark] failed to save bookmark for \(card.friendlyName): \(error)"
            )
        }
    }

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
