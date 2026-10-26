//
//  PlaybackDiagnosticsSettingsView.swift
//  Omnia
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Settings › Playback › Diagnostics: the last playback failures, what
/// Omnia did about each, and Copy to send them along (Dafa, 2026-10-26).
/// Only a stream's host is kept, never its address or tokens.
struct PlaybackDiagnosticsSettingsView: View {
    @State private var entries: [PlaybackFailureEntry] = []
    @State private var didCopy = false

    var body: some View {
        OmniaSettingsForm {
            Section {
                if entries.isEmpty {
                    Text("No playback failures recorded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title + (entry.episode.map { " · \($0)" } ?? ""))
                            .font(.headline)
                        Text("\(entry.addon) · \(entry.host) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        if let outcome = entry.outcome {
                            Label(outcome, systemImage: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Recent Failures")
            } footer: {
                Text("The last \(PlaybackFailureLog.limit) times a source couldn't play. Each lists the add-on and the stream's host, never its full address.")
            }

            Section {
                Button(didCopy ? "Copied" : "Copy Report", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                    copyReport()
                }
                .disabled(entries.isEmpty)
                Button("Clear", systemImage: "trash", role: .destructive) {
                    PlaybackFailureLog.shared.removeAll()
                    entries = []
                }
                .disabled(entries.isEmpty)
            }
        }
        .omniaNavigationTitle("Playback Diagnostics")
        .onAppear { entries = PlaybackFailureLog.shared.entries }
    }

    private func copyReport() {
        let report = PlaybackFailureLog.shared.report
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #else
        UIPasteboard.general.string = report
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
