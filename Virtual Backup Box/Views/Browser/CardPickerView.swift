// CardPickerView.swift
// Virtual Backup Box
//
// Lists all card mirrors available on internal local storage with metadata
// (card name, camera model, image/video counts, total size). Tapping a
// card navigates to its MediaGridView.
//
// Shows an empty state if no card mirrors exist on internal storage.

import SwiftUI

struct CardPickerView: View {

    var viewModel: FileBrowserViewModel

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
        }
        .navigationTitle("Browse Files")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No files to browse")
                .font(.headline)
            Text("Backed-up cards will appear here once files are copied to local storage.")
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
