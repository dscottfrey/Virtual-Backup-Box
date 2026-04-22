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
    @State var showingSourcePickerAtLastLocation = false
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
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .task { viewModel.setup(context: modelContext) }
            .sheet(isPresented: $viewModel.showingSourcePicker) {
                FolderPickerView(
                    initialDirectory: URL(fileURLWithPath: "/"),
                    onPicked: { url in
                        viewModel.showingSourcePicker = false
                        Task { await viewModel.handleSourceSelected(url: url) }
                    },
                    onCancelled: {
                        viewModel.showingSourcePicker = false
                    }
                )
            }
            .sheet(isPresented: $showingSourcePickerAtLastLocation) {
                FolderPickerView(
                    initialDirectory: nil,
                    onPicked: { url in
                        showingSourcePickerAtLastLocation = false
                        Task { await viewModel.handleSourceSelected(url: url) }
                    },
                    onCancelled: {
                        showingSourcePickerAtLastLocation = false
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
}

#Preview {
    SelectionView()
        .modelContainer(
            for: [KnownTarget.self, KnownCard.self,
                  CopySession.self, FileRecord.self],
            inMemory: true
        )
}
