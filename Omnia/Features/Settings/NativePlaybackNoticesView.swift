import SwiftUI

struct NativePlaybackNoticesView: View {
    private enum LoadState {
        case loading
        case loaded([NativePlaybackLegalNotice])
        case unavailable
        case failed(String)
    }

    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading notices…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(notices) where notices.isEmpty:
                ContentUnavailableView(
                    "No Notices Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("The bundled SBOM does not list any native packages.")
                )
            case let .loaded(notices):
                List(notices) { notice in
                    NavigationLink(value: notice) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.name)
                            Text("\(notice.version) · \(notice.licenseExpression)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationDestination(for: NativePlaybackLegalNotice.self) { notice in
                    NativePlaybackNoticeDetailView(notice: notice)
                }
            case .unavailable:
                ContentUnavailableView {
                    Label("Not Included in This Build", systemImage: "shippingbox")
                } description: {
                    Text(
                        "Verified native notices are included with approved Mac distribution builds."
                    )
                } actions: {
                    Button("Retry", action: load)
                }
            case let .failed(message):
                ContentUnavailableView {
                    Label("Notices Couldn’t Be Loaded", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry", action: load)
                }
            }
        }
        .omniaNavigationTitle("Native Playback Notices")
        .task {
            if case .loading = state {
                load()
            }
        }
    }

    private func load() {
        state = .loading
        guard let root = NativePlaybackLegalCatalog.bundledRoot() else {
            state = .unavailable
            return
        }

        Task {
            do {
                let notices = try await Task.detached {
                    try NativePlaybackLegalCatalog.notices(at: root)
                }.value
                state = .loaded(notices)
            } catch NativePlaybackLegalCatalog.CatalogError.unavailable {
                state = .unavailable
            } catch {
                state = .failed(
                    error.localizedDescription.isEmpty
                        ? "The bundled notices failed validation."
                        : error.localizedDescription
                )
            }
        }
    }
}

private struct NativePlaybackNoticeDetailView: View {
    let notice: NativePlaybackLegalNotice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Version", value: notice.version)
                LabeledContent("License", value: notice.licenseExpression)

                Divider()

                Text(notice.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .omniaNavigationTitle(notice.name)
    }
}
