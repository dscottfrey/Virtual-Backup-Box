// SelectionView.swift
// Virtual Backup Box
//
// The main screen of the app — the entry point for every backup session.
// Shows two zones (Target and Source) and a "Start Backup" button that
// activates once both are confirmed. Zone sub-views are in the extension
// file SelectionView+Zones.swift.
//
// This view contains only UI. All business logic lives in SelectionViewModel.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SelectionView: View {

    @Environment(\.modelContext) var modelContext
    @State var viewModel = SelectionViewModel()
    @State var showingManageTargets = false
    @State var showingHistory = false
    @State var showingFileBrowser = false
    @State var showingResetConfirmation = false
    @State var scanViewModel: ScanViewModel?
    @State var navigateToScan = false
    @State var sessionViewModel: SessionViewModel?
    @State var navigateToSession = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                targetZone
                Divider()
                sourceZone
                Spacer()
                startBackupButton
            }
            .padding()
            .navigationTitle("Virtual Backup Box")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFileBrowser = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingHistory = true
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            FolderPickerView.clearBookmark()
                        } label: {
                            Label("Reset Source Bookmark", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            showingResetConfirmation = true
                        } label: {
                            Label("Reset Database", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { viewModel.setup(context: modelContext) }
            .sheet(isPresented: $viewModel.showingSourcePicker) {
                FolderPickerView(
                    onPicked: { url in
                        viewModel.showingSourcePicker = false
                        Task { await viewModel.handleSourceSelected(url: url) }
                    },
                    onCancelled: {
                        viewModel.showingSourcePicker = false
                    }
                )
            }
            .sheet(isPresented: $viewModel.showCardNamingDialog) {
                CardNamingDialog(viewModel: viewModel)
            }
            .sheet(isPresented: $showingManageTargets) {
                ManageTargetsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryBrowserView()
            }
            .sheet(isPresented: $showingFileBrowser) {
                FileBrowserView()
            }
            .confirmationDialog(
                "Reset Database",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset All Records", role: .destructive) {
                    resetDatabase()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This deletes all backup history, file records, known cards, and known targets from the database. Files on disk are not affected. The app will behave as if freshly installed.")
            }
            .navigationDestination(isPresented: $navigateToScan) {
                if let scanVM = scanViewModel {
                    scanFlowView(scanVM)
                }
            }
            .navigationDestination(isPresented: $navigateToSession) {
                sessionDestinationView
            }
        }
    }

    // MARK: - Scan Flow

    @ViewBuilder
    private func scanFlowView(_ scanVM: ScanViewModel) -> some View {
        if let result = scanVM.scanResult {
            ScanSummaryView(
                result: result,
                availableSpaceBytes: scanVM.availableSpaceBytes,
                onStartBackup: {
                    let sessionVM = SessionViewModel()
                    sessionVM.targetName = viewModel.activeTarget?.friendlyName ?? ""
                    sessionVM.startSession(
                        scanResult: result,
                        selectedCard: scanVM.selectedCard,
                        modelContext: modelContext
                    )
                    sessionViewModel = sessionVM
                    navigateToSession = true
                },
                onCancel: { navigateToScan = false }
            )
        } else {
            ScanProgressView(viewModel: scanVM)
                .task { await scanVM.startScan() }
        }
    }

    // MARK: - Session Destination

    @ViewBuilder
    private var sessionDestinationView: some View {
        if let sessionVM = sessionViewModel {
            if sessionVM.isSessionComplete,
               let session = sessionVM.completedSession {
                SessionResultsView(
                    viewModel: ResultsViewModel(
                        session: session,
                        failedFiles: sessionVM.failedFiles,
                        targetName: sessionVM.targetName,
                        modelContext: modelContext
                    ),
                    onDone: {
                        navigateToSession = false
                        navigateToScan = false
                    }
                )
            } else {
                SessionProgressView(viewModel: sessionVM,
                    onSessionComplete: { },
                    onCancel: {
                        navigateToSession = false
                        navigateToScan = false
                    }
                )
            }
        }
    }

    // MARK: - Start Backup Button

    private var startBackupButton: some View {
        Button {
            scanViewModel = ScanViewModel(
                sourceURL: viewModel.sourceURL!,
                targetURL: viewModel.activeTargetURL!,
                sessionFolderName: viewModel.sessionFolderName,
                cameraModel: viewModel.selectedCard?.cameraModel,
                selectedCard: viewModel.selectedCard,
                modelContext: modelContext
            )
            navigateToScan = true
        } label: {
            Text("Start Backup")
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isReady)
    }

    // MARK: - Reset Database

    /// Deletes all SwiftData records (sessions, file records, known cards,
    /// known targets). Files on disk are not affected. The app returns to
    /// a fresh-install state. Useful for clearing stale records during
    /// development or after a schema change.
    private func resetDatabase() {
        let context = modelContext
        let sessions = (try? context.fetch(FetchDescriptor<CopySession>())) ?? []
        for s in sessions { context.delete(s) }
        let cards = (try? context.fetch(FetchDescriptor<KnownCard>())) ?? []
        for c in cards { context.delete(c) }
        let targets = (try? context.fetch(FetchDescriptor<KnownTarget>())) ?? []
        for t in targets { context.delete(t) }
        let records = (try? context.fetch(FetchDescriptor<FileRecord>())) ?? []
        for r in records { context.delete(r) }

        // Reset ViewModel state
        viewModel.activeTarget = nil
        viewModel.activeTargetURL = nil
        viewModel.availableSpaceBytes = nil
        viewModel.sourceURL = nil
        viewModel.selectedCard = nil
        viewModel.sourceDisplayName = ""
        viewModel.resolveKnownTargets()
    }
}

#Preview {
    SelectionView()
        .modelContainer(
            for: [KnownTarget.self, KnownCard.self,
                  CopySession.self, FileRecord.self],
            inMemory: true
        )
}
