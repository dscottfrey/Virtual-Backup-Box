// KnownCardsView.swift
// Virtual Backup Box
//
// Lists all known camera cards with their metadata. Allows renaming
// (display name only — the folder on disk is never changed) and removing
// (deletes the card record and all its session history via cascade delete).
//
// Accessible from the History Browser.

import SwiftUI

struct KnownCardsView: View {

    @Bindable var viewModel: HistoryViewModel

    @State private var showRemoveWarning = false
    @State private var cardToRemove: KnownCard?

    var body: some View {
        List {
            if viewModel.knownCards.isEmpty {
                Text("No cards registered yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.knownCards) { card in
                cardRow(card)
            }
        }
        .navigationTitle("Known Cards")
        .alert("Rename Card", isPresented: .init(
            get: { viewModel.renamingCard != nil },
            set: { if !$0 { viewModel.renamingCard = nil } }
        )) {
            TextField("Card name", text: $viewModel.renameInput)
            Button("Save") {
                if let card = viewModel.renamingCard {
                    let trimmed = viewModel.renameInput.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if !trimmed.isEmpty {
                        viewModel.renameCard(card, to: trimmed)
                    }
                }
                viewModel.renamingCard = nil
            }
            Button("Cancel", role: .cancel) { viewModel.renamingCard = nil }
        }
        .alert("Remove Card?", isPresented: $showRemoveWarning) {
            Button("Remove", role: .destructive) {
                if let card = cardToRemove {
                    viewModel.removeCard(card)
                }
                cardToRemove = nil
            }
            Button("Cancel", role: .cancel) { cardToRemove = nil }
        } message: {
            Text("This will remove the card record and all its backup history. Files on disk are not affected.")
        }
    }

    private func cardRow(_ card: KnownCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.friendlyName)
                .fontWeight(.medium)
            Text(card.cameraModel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text("First seen: \(card.firstSeenDate, format: .dateTime.month().day().year())")
                if let lastBackup = card.lastBackupDate {
                    Text("Last backup: \(lastBackup, format: .dateTime.month().day())")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("\(card.sessions.count) sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                cardToRemove = card
                showRemoveWarning = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            Button {
                viewModel.renameInput = card.friendlyName
                viewModel.renamingCard = card
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
