// SelectionViewModel+Reset.swift
// Virtual Backup Box
//
// Extension on SelectionViewModel that handles the "Reset Database"
// action triggered from the main-screen ellipsis menu. Split into its
// own file so the main ViewModel stays focused on the selection flow
// (§6.3 — one file, one job).

import Foundation
import SwiftData

extension SelectionViewModel {

    /// Deletes every SwiftData record (sessions, file records, known
    /// cards, known targets) and clears in-memory selection state. Files
    /// on disk are not touched. The app behaves as if freshly installed.
    /// Useful during development or after a schema change.
    func resetDatabase() {
        guard let context = modelContext else { return }

        let sessions = (try? context.fetch(FetchDescriptor<CopySession>())) ?? []
        for s in sessions { context.delete(s) }
        let cards = (try? context.fetch(FetchDescriptor<KnownCard>())) ?? []
        for c in cards { context.delete(c) }
        let targets = (try? context.fetch(FetchDescriptor<KnownTarget>())) ?? []
        for t in targets { context.delete(t) }
        let records = (try? context.fetch(FetchDescriptor<FileRecord>())) ?? []
        for r in records { context.delete(r) }

        activeTarget = nil
        activeTargetURL = nil
        availableSpaceBytes = nil
        sourceURL = nil
        selectedCard = nil
        sourceDisplayName = ""
        resolveKnownTargets()
    }
}
