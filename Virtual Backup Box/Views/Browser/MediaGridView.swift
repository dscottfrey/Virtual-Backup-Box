// MediaGridView.swift
// Virtual Backup Box
//
// LazyVGrid of thumbnails with Images/Videos segmented tabs and multi-select
// mode. Tapping a cell in normal mode opens the full-screen viewer; in
// select mode, it toggles the selection.

import SwiftUI

struct MediaGridView: View {

    @Bindable var viewModel: FileBrowserViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var fullScreenIndex: Int?
    @State private var showDeleteConfirm = false

    private var columnCount: Int { sizeClass == .regular ? 4 : 3 }

    var body: some View {
        let files = viewModel.currentFiles
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 0),
            count: columnCount
        )

        VStack(spacing: 0) {
            // Images / Videos tabs
            Picker("Media", selection: $viewModel.currentTab) {
                Text("Images").tag(FileBrowserViewModel.MediaTab.images)
                Text("Videos").tag(FileBrowserViewModel.MediaTab.videos)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Grid
            GeometryReader { geometry in
                let cellSize = geometry.size.width / CGFloat(columnCount)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.url) { index, file in
                            ThumbnailCell(
                                file: file,
                                isVideo: viewModel.currentTab == .videos,
                                isSelecting: viewModel.isSelecting,
                                isSelected: viewModel.selectedURLs.contains(file.url),
                                size: cellSize
                            )
                            .onTapGesture {
                                if viewModel.isSelecting {
                                    viewModel.toggleSelection(file)
                                } else {
                                    fullScreenIndex = index
                                }
                            }
                        }
                    }
                }
            }
        }
        .toolbar { toolbarContent }
        .navigationDestination(item: $fullScreenIndex) { index in
            if viewModel.currentTab == .images {
                FullScreenImageView(
                    files: viewModel.imageFiles,
                    startIndex: index,
                    viewModel: viewModel
                )
            } else {
                FullScreenVideoView(
                    files: viewModel.videoFiles,
                    startIndex: index,
                    viewModel: viewModel
                )
            }
        }
        .confirmationDialog(
            "Delete Files",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                withAnimation { viewModel.deleteSelectedFiles() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(viewModel.deleteConfirmationMessage)
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            ActivityViewWrapper(urls: viewModel.selectedFileURLs)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.isSelecting {
                Button("Cancel") { viewModel.clearSelection() }
            } else {
                Button("Select") { viewModel.isSelecting = true }
            }
        }
        if viewModel.isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Text("\(viewModel.selectedCount) selected")
                    .fontWeight(.medium)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Select All") { viewModel.selectAll() }
                Spacer()
                Button { viewModel.showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.selectedCount == 0)
                Spacer()
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.selectedCount == 0)
            }
        }
    }
}

// MARK: - Share Sheet Wrapper

/// UIViewControllerRepresentable wrapping UIActivityViewController for
/// multi-file sharing. SwiftUI's ShareLink does not support bulk file URL
/// sharing as of iOS 17 — this wrapper uses the documented Apple approach.
struct ActivityViewWrapper: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
