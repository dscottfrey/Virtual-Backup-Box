// FullScreenImageView.swift
// Virtual Backup Box
//
// Full-screen zoomable image viewer with swipe navigation between files.
// Uses ZoomableScrollView (UIViewRepresentable) for pinch-to-zoom. Shows
// filename overlay that auto-hides after 3 seconds. Includes share and
// trash toolbar buttons.

import SwiftUI

struct FullScreenImageView: View {

    let files: [MediaFile]
    let startIndex: Int
    var viewModel: FileBrowserViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var currentImage: UIImage?
    @State private var showOverlay = true
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
                    ZoomableImageContent(url: file.url)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Filename overlay
            if showOverlay, let file = currentFile {
                VStack {
                    Text(file.fileName)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.opacity)
            }
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
            "Delete File",
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
            Text("Delete \(currentFile?.fileName ?? "this file")? This cannot be undone.")
        }
        .onAppear { scheduleOverlayHide() }
        .onChange(of: currentIndex) { scheduleOverlayHide() }
    }

    private func scheduleOverlayHide() {
        showOverlay = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { showOverlay = false }
        }
    }
}

/// Loads and displays a full-resolution image for one page of the viewer.
private struct ZoomableImageContent: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableScrollView(image: image)
            } else {
                ProgressView()
            }
        }
        .task {
            image = await ThumbnailService.shared.fullImage(for: url)
        }
    }
}
