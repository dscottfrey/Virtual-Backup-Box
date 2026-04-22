// FileBrowserView.swift
// Virtual Backup Box
//
// Entry point for the file browser. Shows the card picker if multiple
// card mirrors exist, or navigates directly to the grid if there is only
// one. Presented as a sheet from the main selection screen.

import SwiftUI
import SwiftData

struct FileBrowserView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = FileBrowserViewModel()

    var body: some View {
        NavigationStack {
            CardPickerView(viewModel: viewModel)
                .task {
                    viewModel.setup(context: modelContext)
                }
        }
    }
}
