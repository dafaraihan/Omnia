//
//  AddonDiagnostics.swift
//  Omnia
//

import Foundation
import Observation

/// What happened the last time Omnia talked to each add-on, so Settings can
/// say why a catalog or a collection folder is empty instead of showing
/// nothing. Kept for this session only; nothing here leaves the device.
@MainActor
@Observable
final class AddonDiagnostics {
    static let shared = AddonDiagnostics()

    enum Resource: String, CaseIterable, Identifiable, Sendable {
        case manifest
        case catalog
        case meta
        case stream
        case subtitles

        var id: String { rawValue }

        var title: String {
            switch self {
            case .manifest: "Manifest"
            case .catalog: "Catalogs"
            case .meta: "Details"
            case .stream: "Streams"
            case .subtitles: "Subtitles"
            }
        }

        /// The manifest resource name this request uses.
        var manifestName: String? {
            switch self {
            case .manifest: nil
            case .catalog: "catalog"
            case .meta: "meta"
            case .stream: "stream"
            case .subtitles: "subtitles"
            }
        }
    }

    struct Failure: Equatable, Sendable {
        let date: Date
        let message: String
    }

    struct Status: Equatable, Sendable {
        var lastSuccess: Date?
        var lastFailure: Failure?

        /// True when the most recent request failed.
        var isFailing: Bool {
            guard let lastFailure else { return false }
            return lastSuccess.map { lastFailure.date > $0 } ?? true
        }
    }

    struct Report: Equatable, Sendable {
        var resources: [Resource: Status] = [:]
        /// Catalogs whose most recent request failed, by `type/id`.
        var failingCatalogs: [String: Failure] = [:]

        var hasProblem: Bool {
            resources.values.contains(where: \.isFailing) || !failingCatalogs.isEmpty
        }
    }

    private(set) var reports: [String: Report] = [:]

    func report(for addon: InstalledAddon) -> Report {
        reports[addon.id] ?? Report()
    }

    func catalogFailure(addon: InstalledAddon, catalog: AddonCatalog) -> Failure? {
        reports[addon.id]?.failingCatalogs[Self.catalogKey(catalog)]
    }

    func recordSuccess(_ resource: Resource, addon: InstalledAddon, catalog: AddonCatalog? = nil) {
        recordSuccess(resource, addonID: addon.id, catalog: catalog)
    }

    func recordSuccess(_ resource: Resource, addonID: String, catalog: AddonCatalog? = nil) {
        var report = reports[addonID] ?? Report()
        report.resources[resource, default: Status()].lastSuccess = .now
        if let catalog { report.failingCatalogs[Self.catalogKey(catalog)] = nil }
        reports[addonID] = report
    }

    func recordFailure(_ resource: Resource, addon: InstalledAddon, catalog: AddonCatalog? = nil, error: Error) {
        recordFailure(resource, addonID: addon.id, catalog: catalog, error: error)
    }

    func recordFailure(_ resource: Resource, addonID: String, catalog: AddonCatalog? = nil, error: Error) {
        // Leaving a screen cancels its requests; that isn't the add-on's fault.
        guard !Self.isCancellation(error) else { return }
        let failure = Failure(date: .now, message: Self.message(for: error))
        var report = reports[addonID] ?? Report()
        report.resources[resource, default: Status()].lastFailure = failure
        if let catalog { report.failingCatalogs[Self.catalogKey(catalog)] = failure }
        reports[addonID] = report
    }

    static func catalogKey(_ catalog: AddonCatalog) -> String {
        "\(catalog.type)/\(catalog.id)"
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case HTTPTransportError.cancelled = error { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// A sentence a person can act on, from any error the add-on layer throws.
    static func message(for error: Error) -> String {
        switch error {
        case HTTPTransportError.timedOut:
            return "The add-on didn't answer in time."
        case let HTTPTransportError.unsuccessfulStatus(status):
            switch status {
            case 401, 403: return "The add-on refused the request (\(status)). Its configuration may have expired."
            case 404: return "The add-on doesn't have this (404)."
            case 429: return "The add-on is limiting requests (429). Try again later."
            case 500...599: return "The add-on's server had an error (\(status))."
            default: return "The add-on answered with status \(status)."
            }
        case HTTPTransportError.transportFailure:
            return "The add-on couldn't be reached. Check your connection."
        case HTTPTransportError.responseTooLarge:
            return "The add-on's answer was too large."
        case StremioAddonClient.AddonClientError.invalidResponse, HTTPTransportError.invalidResponse:
            return "The add-on's answer wasn't valid add-on data."
        case let error as LocalizedError:
            return error.errorDescription ?? error.localizedDescription
        default:
            return error.localizedDescription
        }
    }
}
