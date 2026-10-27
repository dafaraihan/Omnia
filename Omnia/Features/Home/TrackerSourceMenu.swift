//
//  TrackerSourceMenu.swift
//  Omnia
//

import SwiftUI

/// The chevron menu beside Continue Watching, like Nuvio's: switch between
/// Omnia's own progress and a connected tracker's, sync it now, or clear
/// what was read from it (Dafa, 2026-10-27).
struct TrackerSourceMenu: View {
    @Binding var selection: TrackerLibrarySource
    @Environment(OmniaStore.self) private var store
    @State private var trackers = TrackerLibraryStore.shared

    private var source: TrackerLibrarySource { trackers.effectiveSource(selection) }

    var body: some View {
        Menu {
            Picker("Source", selection: $selection) {
                ForEach(trackers.availableSources) { option in
                    Text("All \(option.title)").tag(option)
                }
            }
            .pickerStyle(.inline)

            if let kind = source.tracker {
                Divider()
                Button("Sync \(kind.shortTitle) Now", systemImage: "arrow.triangle.2.circlepath") {
                    trackers.sync(kind, addons: store.installedAddons)
                }
                .disabled(trackers.state(kind) == .syncing)
                Button("Clear \(kind.shortTitle) Cache", systemImage: "trash") {
                    trackers.clearCache(kind, addons: store.installedAddons)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let kind = source.tracker, trackers.state(kind) == .syncing {
                    ProgressView().controlSize(.mini)
                } else if let kind = source.tracker {
                    TrackerMark(kind: kind)
                        .scaleEffect(0.7)
                        .frame(width: 17, height: 17)
                }
                Text(source.title)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Where Continue Watching comes from")
        .accessibilityLabel("Continue Watching source")
        .accessibilityValue(source.title)
    }
}

/// A tracker's sync problem, shown under its row.
struct TrackerSyncStatusLine: View {
    let kind: TrackerKind
    @State private var trackers = TrackerLibraryStore.shared

    var body: some View {
        if case .failed(let message) = trackers.state(kind) {
            Label("Couldn't sync \(kind.shortTitle): \(message)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
