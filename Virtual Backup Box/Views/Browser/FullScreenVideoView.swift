// FullScreenVideoView.swift
// Virtual Backup Box
//
// Full-screen video player with swipe navigation between video files.
// Uses AVKit's VideoPlayer — the correct Apple framework for video
// playback on iOS. Includes share and trash toolbar buttons.

import SwiftUI
import AVKit

struct FullScreenVideoView: View {

    let files: [MediaFile]
    let startIndex: Int
    var viewModel: FileBrowserViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showDeleteConfirm = false

    init(files: [MediaFile], startIndex: Int, viewModel: FileBrowserViewModel) {
        self.files = files
        self.startIndex = startIndex
        self.viewModel = viewModel
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentFile: MediaFile? {
        guard files.indices.contains(currentIndex) else { return nil }
        return files[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(files.enumerated()), id: \.element.url) { index, file in
                    VideoPlayer(player: AVPlayer(url: file.url))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    ShareLink(item: currentFile?.url ?? URL(fileURLWithPath: "")) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Video",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let file = currentFile {
                    viewModel.deleteSingleFile(file)
                    if files.isEmpty { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Delete \(currentFile?.fileName ?? "this video")? This cannot be undone.")
        }
    }
}
