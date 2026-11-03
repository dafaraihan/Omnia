//
//  AddonHomeCatalogRow.swift
//  Omnia
//

import SwiftUI

/// One add-on catalog on Home in add-on mode. Data comes from the shared
/// `AddonCatalogStore`; a row that loaded with no titles is left out, as in
/// Nuvio, while a failed row stays visible with Retry.
struct AddonHomeCatalogRow: View {
    @Environment(\.displayPreferences) private var display
    let catalog: AddonHomeCatalog
    let title: String
    let items: [MediaItem]
    let state: AddonCatalogStore.RowState?
    let retry: () -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeaderLink(title: title) {
                    AddonCatalogBrowseView(addon: catalog.addon, catalog: catalog.catalog)
                }
                ShelfScrollView(
                    items: items,
                    itemSpan: MediaBrowseMetrics.posterItemSpan(display),
                    accessibilityLabel: title
                ) { item in
                    MediaPoster(item: item)
                }
            }
        } else if state == .loading || state == nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title)
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading \(title)")
            }
        } else if state == .failed {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: title)
                Text("\(catalog.addon.displayName) didn't respond.")
                    .foregroundStyle(.secondary)
                Button("Retry", systemImage: "arrow.clockwise", action: retry)
            }
        }
    }
}

/// A small deterministic generator, so the hero keeps the same shuffled order
/// across redraws and only reshuffles when the catalogs reload.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
