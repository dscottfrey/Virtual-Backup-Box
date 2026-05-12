// SelectionView.swift
// Virtual Backup Box
//
// The main screen of the app — the entry point for every backup session.
// Shows two zones (Source on top, Target below). Tapping "Verify Backup Flow" runs
// the Module 2 scan inline below the zones (see InlineScanCard); tapping
// "Start Copying" inside that card pushes to the live session page.
//
// Why inline-scan instead of pushing a separate "Scan Complete" page:
// the user shouldn't lose sight of which Source and Target a scan is
// reporting on. The previous flow added a middle page that was little
// more than "tap to confirm" — folding it into the main screen removes
// the navigation step without losing any information.
//
// This view contains only UI. All business logic lives in SelectionViewModel.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SelectionView: View {

    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    @State var viewModel = SelectionViewModel()
    @State var showingManageTargets = false
    @State var showingHistory = false
    @State var showingFileBrowser = false
    @State var showingResetConfirmation = false
    @State var showingSettings = false
    @State var scanViewModel: ScanViewModel?
    @State var sessionViewModel: SessionViewModel?
    @State var navigateToSession = false

    /// UUIDs of KnownCards whose stored bookmark resolves to a reachable
    /// URL right now — i.e. cards plugged in *and* with sandbox access
    /// already granted. Populated by
    /// SelectionView+MountedCards.refreshMountedCards(). Drives whether
    /// the "Select Previous" button is enabled and which helper text the
    /// source zone shows under the known-cards picker.
    @State var mountedCardUUIDs: Set<String> = []

    /// UUID of the KnownCard currently chosen in the source zone's
    /// "Known cards" pulldown. Defaults on appear to the most-recently
    /// backed-up card that isn't the current source. Stored as a String
    /// so the binding survives SwiftData object refresh.
    @State var selectedKnownCardUUID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    sourceZone
                    targetZone
                    if let scanVM = scanViewModel {
                        InlineScanCard(
                            viewModel: scanVM,
                            onStartCopying: { startCopying(scanVM: scanVM) },
                            onDismiss: { scanViewModel = nil }
                        )
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                if scanViewModel == nil {
                    startBackupButton
                        .padding()
                        .background(.bar)
                }
            }
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
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                        Divider()
                        Button {
                            FolderPickerView.clearBookmark()
                        } label: {
                            Label("Forget Last Source", systemImage: "arrow.uturn.backward")
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
            .task {
                viewModel.setup(context: modelContext)
                refreshMountedCards()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Coming back from background often means a card was just
                // plugged in or pulled. Refresh so the "Known cards" rows
                // flip between actionable and gray immediately.
                if newPhase == .active { refreshMountedCards() }
            }
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
            .sheet(isPresented: $showingSettings) {
                SettingsView()
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
            // A summary built from the previous Source/Target shouldn't linger
            // once those inputs change. Easier (and safer) to clear and let
            // the user re-tap "Verify Backup Flow" than to keep a stale card.
            // Logs are temporary — diagnosing a freeze on the card naming
            // dialog Confirm button. Remove once the cause is found.
            //
            // Also refresh the mounted-cards set on every sourceURL change.
            // Without this, after a successful Select New the picker keeps
            // showing the just-picked card as "not plugged in" until the
            // user backgrounds and returns (Scott 2026-05-12). Refreshing
            // here makes the picker reflect reality immediately.
            .onChange(of: viewModel.sourceURL) {
                DebugLogService.shared.log("[onChange sourceURL] firing — clearing scanViewModel + refreshing mounted cards")
                scanViewModel = nil
                refreshMountedCards()
            }
            .onChange(of: viewModel.activeTargetURL) {
                DebugLogService.shared.log("[onChange activeTargetURL] firing — clearing scanViewModel")
                scanViewModel = nil
            }
            .navigationDestination(isPresented: $navigateToSession) {
                sessionDestinationView
            }
        }
    }

    // MARK: - Start Scan

    /// Builds a fresh ScanViewModel, stores it so InlineScanCard appears,
    /// and kicks off the scan task. Triggered by the Verify Backup Flow
    /// button. Hand-off into the live session lives in
    /// SelectionView+SessionRoute.swift.
    ///
    /// Validates the source one more time at the moment of the tap. If
    /// the card was pulled or swapped after Select Previous (and before
    /// refreshMountedCards next ran), the source URL is stale. The
    /// validator clears the source and returns false; we bail without
    /// scanning. The Verify button will disable on the next render.
    private func startScan() {
        guard viewModel.validateSourceStillValid() else {
            DebugLogService.shared.log(
                "[startScan] source no longer valid — aborting scan"
            )
            return
        }
        let scanVM = ScanViewModel(
            sourceURL: viewModel.sourceURL!,
            targetURL: viewModel.activeTargetURL!,
            sessionFolderName: viewModel.sessionFolderName,
            cameraModel: viewModel.selectedCard?.cameraModel,
            selectedCard: viewModel.selectedCard,
            modelContext: modelContext
        )
        scanViewModel = scanVM
        Task { await scanVM.startScan() }
    }

    // MARK: - Verify Backup Flow Button

    private var startBackupButton: some View {
        Button {
            startScan()
        } label: {
            Text("Verify Backup Flow")
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isReady)
    }

    // MARK: - Reset Database

    /// Wraps the ViewModel's resetDatabase so the view can also clear its
    /// own scan-card state in a single call site.
    private func resetDatabase() {
        viewModel.resetDatabase()
        scanViewModel = nil
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
