// ManageTargetsView.swift
// Virtual Backup Box
//
// Presented as a sheet from SelectionView. Shows all known backup targets
// with their availability status. The user can add new targets, rename
// existing ones, remove them, or tap one to make it the active target.
//
// Adding a target opens the system folder picker, then prompts for a
// friendly name. The bookmark and name are saved to SwiftData.
//
// Availability refresh (2026-05-13): the target list re-resolves every
// time this sheet appears AND on scenePhase → .active while the sheet is
// up. Scott reported that an already-known flash drive showed as gray
// (unavailable) and tapping it did nothing, forcing him to Add External
// Destination and create a duplicate. Refreshing on appearance picks up
// drives that were plugged in after the SelectionView's initial resolve.
//
// Duplicate avoidance: handleTargetSelected now returns a
// TargetPickResult enum. When the picked URL matches a known target's
// resolved path, that existing target is activated silently and the
// naming alert is skipped — no duplicate created.

import SwiftUI
import UniformTypeIdentifiers

struct ManageTargetsView: View {

    var viewModel: SelectionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Controls the file picker for adding a new target.
    @State private var showingPicker = false

    /// Controls the name-entry alert after picking a target folder.
    @State private var showingNamePrompt = false

    /// Holds the name being entered in the naming alert.
    @State private var nameInput = ""

    /// The target currently being renamed (nil when not renaming).
    @State private var renamingTarget: KnownTarget?

    /// The text being entered for a rename.
    @State private var renameInput = ""

    var body: some View {
        NavigationStack {
            List {
                if viewModel.allTargets.isEmpty {
                    Text("No destinations saved yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.allTargets) { target in
                    targetRow(target)
                }

                if !viewModel.hasInternalStorageTarget {
                    Button {
                        viewModel.addInternalStorageTarget()
                    } label: {
                        Label("Use VBB Internal Storage", systemImage: "ipad")
                    }
                }

                Button {
                    showingPicker = true
                } label: {
                    Label("Add External Destination", systemImage: "plus")
                }
            }
            .navigationTitle("Manage Destinations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.folder]
            ) { result in
                guard case .success(let url) = result else { return }
                switch viewModel.handleTargetSelected(url: url) {
                case .new:
                    nameInput = viewModel.pendingTargetName
                    showingNamePrompt = true
                case .existing:
                    // Existing target was activated silently. Close the
                    // sheet so the user sees the now-active destination
                    // back on the main screen — the action they were
                    // ultimately trying to take.
                    dismiss()
                case .failed:
                    // Bookmark or security-scope failure. Silent for now;
                    // user can retry. Surfacing an alert here is on the
                    // deferred list.
                    break
                }
            }
            .task { viewModel.resolveKnownTargets() }
            .onChange(of: scenePhase) { _, newPhase in
                // Coming back from background often means a drive was
                // just plugged in (or pulled). Re-resolve so the list's
                // green/gray dots reflect reality before the user taps.
                if newPhase == .active {
                    viewModel.resolveKnownTargets()
                }
            }
            .alert("Name This Destination", isPresented: $showingNamePrompt) {
                TextField("Name", text: $nameInput)
                Button("Save") {
                    let trimmed = nameInput.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if !trimmed.isEmpty {
                        viewModel.confirmTargetName(trimmed)
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.pendingBookmarkData = nil
                }
            } message: {
                Text("Enter a name for this backup destination.")
            }
            .alert("Rename Destination", isPresented: .init(
                get: { renamingTarget != nil },
                set: { if !$0 { renamingTarget = nil } }
            )) {
                TextField("Name", text: $renameInput)
                Button("Save") {
                    if let target = renamingTarget {
                        let trimmed = renameInput.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        if !trimmed.isEmpty {
                            viewModel.renameTarget(target, to: trimmed)
                        }
                    }
                    renamingTarget = nil
                }
                Button("Cancel", role: .cancel) { renamingTarget = nil }
            }
        }
    }

    // MARK: - Target Row

    /// One row in the target list showing name, availability, and last-used
    /// date. Tap to make active; swipe for rename/remove.
    private func targetRow(_ target: KnownTarget) -> some View {
        let available = viewModel.targetAvailability[
            ObjectIdentifier(target)
        ] ?? false

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.friendlyName)
                if let lastUsed = target.lastUsedDate {
                    Text("Last used \(lastUsed, format: .dateTime.month().day())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: available ? "circle.fill" : "circle")
                .foregroundStyle(available ? .green : .gray)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // If the row is currently gray, refresh availability first —
            // the drive may have become available since the list was
            // last resolved (common when plugging in a drive while this
            // sheet is open and scenePhase hasn't changed).
            if !available {
                viewModel.resolveKnownTargets()
            }

            let nowAvailable = viewModel.targetAvailability[
                ObjectIdentifier(target)
            ] ?? false
            guard nowAvailable else { return }

            viewModel.selectTarget(target)
            if viewModel.activeTarget === target {
                dismiss()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.removeTarget(target)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            Button {
                renameInput = target.friendlyName
                renamingTarget = target
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
