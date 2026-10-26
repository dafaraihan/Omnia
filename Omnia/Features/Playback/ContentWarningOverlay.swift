//
//  ContentWarningOverlay.swift
//  Omnia
//

import SwiftUI

/// Nuvio's Parental Guide overlay: once the first frame is on screen, the
/// title's content warnings appear beside an accent line for a few
/// seconds, then fade (Dafa, 2026-10-26).
struct ContentWarningOverlay: View {
    let item: MediaItem?
    /// Changes for each episode, so every episode shows them once.
    let playbackKey: String
    let hasStarted: Bool
    let isEnabled: Bool

    @Environment(\.displayPreferences) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var warnings: [ContentWarning] = []
    @State private var isVisible = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(display.accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(warnings, id: \.self) { warning in
                    HStack(spacing: 0) {
                        Text(warning.category)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.9))
                        Text(" · ")
                            .foregroundStyle(.white.opacity(0.4))
                        Text(warning.severity.title)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .font(.callout)
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.6), radius: 6)
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible || reduceMotion ? 0 : -12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHidden(!isVisible)
        .task(id: "\(playbackKey)|\(hasStarted)|\(isEnabled)") {
            await show()
        }
    }

    private func show() async {
        withAnimation(.easeOut(duration: 0.2)) { isVisible = false }
        guard isEnabled, hasStarted, let item else { return }
        let imdb = item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"] ?? item.id
        let found = await ContentWarningClient.shared.warnings(forIMDbID: imdb)
        guard !Task.isCancelled, !found.isEmpty else { return }
        warnings = found
        withAnimation(.easeOut(duration: 0.4)) { isVisible = true }
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.4)) { isVisible = false }
    }

    private var accessibilityText: String {
        "Content warnings: " + warnings.map { "\($0.category), \($0.severity.title)" }.joined(separator: "; ")
    }
}
