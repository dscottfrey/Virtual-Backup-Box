// CardPickerView.swift
// Virtual Backup Box
//
// Lists all card mirrors available on internal local storage with metadata
// (card name, camera model, image/video counts, total size). Tapping a
// card navigates to its MediaGridView.
//
// A "Choose Folder…" entry sits below the card list so the user can also
// browse any folder reachable via the system file picker — iCloud Drive,
// an external drive, a third-party file-provider location. This was added
// 2026-05-13 alongside the source-zone simplification so the Browse view
// works the same way as Source: one pick, anywhere on the device.
//
// Shows an empty-state hint if no card mirrors exist, but the Choose Folder
// button remains accessible so an empty browser is still useful.

import SwiftUI

struct CardPickerView: View {

    var viewModel: FileBrowserViewModel

    /// Drives the FolderPickerView sheet for arbitrary-folder browsing.
    @State private var showFolderPicker = false

    /// When non-nil, the navigationDestination below pushes MediaGridView
    /// for an arbitrary folder. Reset to nil when the user backs out,
    /// which is the cue to release the URL's security scope.
    @State private var arbitraryFolderURL: URL?

    var body: some View {
        List {
            if viewModel.cardMirrors.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.cardMirrors) { mirror in
                    NavigationLink {
                        MediaGridView(viewModel: viewModel)
                            .onAppear { viewModel.selectCard(mirror) }
                            .navigationTitle(mirror.cardName ?? mirror.folderName)
                    } label: {
                        cardRow(mirror)
                    }
                }
            }

            // Choose Folder entry — always visible regardless of whether
            // any card mirrors were found, so a fresh install (no mirrors
            // yet) still has a way into the file browser.
            Section {
                Button {
                    showFolderPicker = true
                } label: {
                    Label("Choose Folder\u{2026}", systemImage: "folder")
                }
            } footer: {
                Text("Browse media in any folder you can reach in Files — iCloud Drive, an external drive, or a third-party cloud service.")
            }
        }
        .navigationTitle("Browse Files")
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(
                onPicked: { url in
                    showFolderPicker = false
                    arbitraryFolderURL = url
                },
                onCancelled: {
                    showFolderPicker = false
                }
            )
        }
        .navigationDestination(item: $arbitraryFolderURL) { url in
            MediaGridView(viewModel: viewModel)
                .onAppear { viewModel.loadArbitraryFolder(url: url) }
                .onDisappear { viewModel.releaseArbitraryFolderAccess() }
                .navigationTitle(url.lastPathComponent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No card backups on this device yet")
                .font(.headline)
            Text("Backed-up cards will appear here once files are copied to local storage. You can also browse any folder using the option below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .listRowBackground(Color.clear)
    }

    private func cardRow(_ mirror: CardMirror) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mirror.cardName ?? mirror.folderName)
                .fontWeight(.medium)
            if let model = mirror.cameraModel {
                Text(model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if mirror.imageCount > 0 {
                    Label("\(mirror.imageCount)", systemImage: "photo")
                }
                if mirror.videoCount > 0 {
                    Label("\(mirror.videoCount)", systemImage: "video")
                }
                Spacer()
                Text(ByteCountFormatter.string(
                    fromByteCount: mirror.totalSizeBytes, countStyle: .file
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
