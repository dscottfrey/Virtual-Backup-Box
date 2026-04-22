// ContentView.swift
// Virtual Backup Box
//
// Root view of the app. Hosts SelectionView (Module 1), which is the entry
// point for every backup session.

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        SelectionView()
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [KnownTarget.self, KnownCard.self,
                  CopySession.self, FileRecord.self],
            inMemory: true
        )
}
