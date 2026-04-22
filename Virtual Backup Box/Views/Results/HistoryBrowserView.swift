// HistoryBrowserView.swift
// Virtual Backup Box
//
// Persistent screen accessible from the main navigation. Shows all past
// backup sessions grouped by source card/folder, with stale session
// detection and cleanup options.

import SwiftUI
import SwiftData

struct HistoryBrowserView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            List {
                // Stale session banner
                if viewModel.showStaleBanner {
                    staleBanner
                }

                // Grouped sessions
                if viewModel.groups.isEmpty {
                    Text("No backup history yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.groups) { group in
                    Section(group.name) {
                        ForEach(group.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                sessionRow(session)
                            }
                        }
                    }
                }

                // Management section
                Section {
                    NavigationLink("Known Cards") {
                        KnownCardsView(viewModel: viewModel)
                    }

                    Button("Clear History\u{2026}") {
                        viewModel.showClearHistoryOptions = true
                    }
                }
            }
            .navigationTitle("History")
            .task {
                viewModel.setup(context: modelContext)
                await viewModel.detectStaleSessions()
            }
            .confirmationDialog(
                "Clear History",
                isPresented: $viewModel.showClearHistoryOptions
            ) {
                Button("Clear All History", role: .destructive) {
                    viewModel.clearAllHistory()
                }
                Button("Older Than 30 Days") {
                    viewModel.clearSessionsOlderThan(days: 30)
                }
                Button("Older Than 90 Days") {
                    viewModel.clearSessionsOlderThan(days: 90)
                }
                Button("Older Than 1 Year") {
                    viewModel.clearSessionsOlderThan(days: 365)
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    // MARK: - Stale Banner

    private var staleBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(viewModel.staleSessionIDs.count) sessions reference drives that are no longer available.")
                .font(.subheadline)
            Button("Remove Them") {
                viewModel.removeStaleSessionsOnly()
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: CopySession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sourceCard?.friendlyName
                     ?? URL(fileURLWithPath: session.sourcePath).lastPathComponent)
                    .fontWeight(.medium)
                Text(session.startDate, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(session.filesCopied) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if viewModel.isSessionStale(session) {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            statusIcon(for: session.status)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: SessionStatus) -> some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .partialSuccess:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .interrupted:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .inProgress:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
}
