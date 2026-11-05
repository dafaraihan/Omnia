import Foundation

/// Follows the system's Low Power Mode for the setting of the same name.
@MainActor
@Observable
final class LowPowerMonitor {
    static let shared = LowPowerMonitor()

    private(set) var isSystemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// A hot device cuts the same effects as Low Power Mode until it cools down.
    private(set) var isThermallyConstrained = LowPowerMonitor.isConstrained(ProcessInfo.processInfo.thermalState)
    private var observer: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSystemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isThermallyConstrained = Self.isConstrained(ProcessInfo.processInfo.thermalState)
            }
        }
    }

    private nonisolated static func isConstrained(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    func isActive(_ mode: LowPowerMode) -> Bool {
        switch mode {
        case .automatic: isSystemLowPower || isThermallyConstrained
        case .on: true
        case .off: false
        }
    }
}
