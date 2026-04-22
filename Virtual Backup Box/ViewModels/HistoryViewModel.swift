// HistoryViewModel.swift
// Virtual Backup Box
//
// Fetches and groups backup sessions from SwiftData for the history browser.
// Handles stale session detection (target volumes no longer accessible),
// history cleanup (clear all or by age), and KnownCard management.

import Foundation
import SwiftData
import Observation

/// A group of sessions sharing the same source card or folder.
struct SessionGroup: Identifiable {
    let id: String
    let name: String
    var sessions: [CopySession]
}

@Observable
class HistoryViewModel {

    var modelContext: ModelContext?
    var sessions: [CopySession] = []
    var groups: [SessionGroup] = []
    var knownCards: [KnownCard] = []

    // MARK: - Stale Session Detection

    /// Object IDs of sessions whose target volume is no longer accessible.
    var staleSessionIDs: Set<ObjectIdentifier> = []

    /// True when stale sessions were found and the banner should show.
    var showStaleBanner = false

    // MARK: - Cleanup State

    var showClearHistoryOptions = false

    // MARK: - Card Rename

    var renamingCard: KnownCard?
    var renameInput = ""

    // MARK: - Setup

    func setup(context: ModelContext) {
        self.modelContext = context
        refresh()
    }

    /// Fetches all sessions and cards, groups sessions, and detects stale ones.
    func refresh() {
        guard let context = modelContext else { return }

        let sessionDescriptor = FetchDescriptor<CopySession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        sessions = (try? context.fetch(sessionDescriptor)) ?? []

        let cardDescriptor = FetchDescriptor<KnownCard>(
            sortBy: [SortDescriptor(\.firstSeenDate, order: .reverse)]
        )
        knownCards = (try? context.fetch(cardDescriptor)) ?? []

        buildGroups()
    }

    /// Groups sessions by source card name or source folder name.
    private func buildGroups() {
        var groupMap: [String: [CopySession]] = [:]
        for session in sessions {
            let key = session.sourceCard?.friendlyName
                ?? URL(fileURLWithPath: session.sourcePath).lastPathComponent
            groupMap[key, default: []].append(session)
        }
        groups = groupMap.map { SessionGroup(id: $0.key, name: $0.key, sessions: $0.value) }
            .sorted { ($0.sessions.first?.startDate ?? .distantPast) >
                      ($1.sessions.first?.startDate ?? .distantPast) }
    }

    /// Checks each session's target path for accessibility. Runs the I/O
    /// check in a background task; updates stale state on the main actor.
    func detectStaleSessions() async {
        let pathsToCheck: [(ObjectIdentifier, String)] = sessions.map {
            (ObjectIdentifier($0), $0.targetPath)
        }

        let staleIDs = await Task.detached {
            var stale: Set<ObjectIdentifier> = []
            for (id, path) in pathsToCheck {
                if !FileManager.default.isReadableFile(atPath: path) {
                    stale.insert(id)
                }
            }
            return stale
        }.value

        staleSessionIDs = staleIDs
        showStaleBanner = !staleIDs.isEmpty
    }

    // MARK: - History Cleanup

    /// Removes all CopySession and FileRecord entries. Does NOT remove
    /// KnownCard or KnownTarget records — those represent registered
    /// hardware, not session history.
    func clearAllHistory() {
        guard let context = modelContext else { return }
        for session in sessions { context.delete(session) }
        refresh()
    }

    /// Removes sessions older than the given number of days.
    func clearSessionsOlderThan(days: Int) {
        guard let context = modelContext,
              let cutoff = Calendar.current.date(
                  byAdding: .day, value: -days, to: Date()
              ) else { return }
        for session in sessions where session.startDate < cutoff {
            context.delete(session)
        }
        refresh()
    }

    /// Removes only sessions flagged as stale (target unreachable).
    func removeStaleSessionsOnly() {
        guard let context = modelContext else { return }
        for session in sessions {
            if staleSessionIDs.contains(ObjectIdentifier(session)) {
                context.delete(session)
            }
        }
        staleSessionIDs = []
        showStaleBanner = false
        refresh()
    }

    // MARK: - Card Management

    func renameCard(_ card: KnownCard, to newName: String) {
        card.friendlyName = newName
        refresh()
    }

    /// Deletes a KnownCard and all its session history (cascade delete).
    func removeCard(_ card: KnownCard) {
        guard let context = modelContext else { return }
        context.delete(card)
        refresh()
    }

    func isSessionStale(_ session: CopySession) -> Bool {
        staleSessionIDs.contains(ObjectIdentifier(session))
    }
}
