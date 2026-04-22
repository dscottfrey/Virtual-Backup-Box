// KnownCard.swift
// Virtual Backup Box
//
// Represents one generation of a physical camera card. "Generation" means one
// format cycle — when a card is reformatted in-camera, the camera writes a new
// filesystem UUID. From the app's perspective that is a brand-new card, and it
// gets a brand-new KnownCard record. The old record stays in the database as a
// permanent archive reference. This is intentional and matches the
// reformat-as-archive model described in §5d of the overall directive.
//
// The UUID is the primary identifier. It is read from the card volume via
// URLResourceKey.volumeUUIDStringKey — a standard Apple API, no jailbreak or
// private framework needed. The UUID is internal only: it is never shown to
// the user and never appears in any folder name on disk.
//
// The camera model string is stored explicitly (not inferred at runtime from
// EXIF) because a freshly reformatted card may have no media files to read
// EXIF from. Storing it also supports the settings restore stretch goal (§9.1),
// which needs to look up "what settings backups exist for this camera model?"

import Foundation
import SwiftData

@Model
final class KnownCard {

    // MARK: - Stored Properties

    /// The card's filesystem volume UUID, read via
    /// URLResourceKey.volumeUUIDStringKey. This never changes for the life
    /// of this card generation. Used to recognise a card on re-insertion
    /// without user input.
    var uuid: String

    /// User-assigned name, confirmed in the naming dialog on first insertion.
    /// Example: "EOS R6 Mark III Card-1"
    /// Can be renamed later from the Known Cards management screen (Module 6).
    var friendlyName: String

    /// Camera model string extracted from EXIF/metadata on first insertion
    /// and confirmed by the user in the naming dialog.
    /// Example: "Canon EOS R6 Mark III"
    /// Stored explicitly — see file header comment for why.
    var cameraModel: String

    /// The folder name created at the target root for this card's mirror.
    /// Format: "YYYYMMDD_[friendlyName]" — date is the date of first backup.
    /// Example: "20260421_EOS R6 Mark III Card-1"
    /// Set once at first backup and never changed, even if the user later
    /// renames the card. This prevents breaking incremental comparison, which
    /// uses paths that include this folder name.
    var destinationFolderName: String

    /// When this card was first seen by the app (i.e. when the naming dialog
    /// was completed for the first time).
    var firstSeenDate: Date

    /// When the most recent successful backup session for this card completed.
    /// Nil if the card has been named but never successfully backed up.
    /// Updated by BackupSessionService (Module 3) at the end of each session.
    var lastBackupDate: Date?

    // MARK: - Relationships

    /// All backup sessions involving this card as source.
    /// Cascade delete: removing a KnownCard removes all its session history.
    /// The inverse relationship is CopySession.sourceCard.
    @Relationship(deleteRule: .cascade, inverse: \CopySession.sourceCard)
    var sessions: [CopySession] = []

    // MARK: - Initialiser

    /// Creates a new KnownCard record.
    ///
    /// Called by Module 1 when the user confirms the naming dialog for a
    /// card with an unknown UUID.
    ///
    /// - Parameters:
    ///   - uuid: The card's filesystem volume UUID.
    ///   - friendlyName: The user-confirmed display name.
    ///   - cameraModel: The confirmed camera model string from EXIF.
    ///   - destinationFolderName: The computed folder name (YYYYMMDD_friendlyName).
    init(uuid: String,
         friendlyName: String,
         cameraModel: String,
         destinationFolderName: String) {
        self.uuid = uuid
        self.friendlyName = friendlyName
        self.cameraModel = cameraModel
        self.destinationFolderName = destinationFolderName
        self.firstSeenDate = Date()
        self.lastBackupDate = nil
    }
}
