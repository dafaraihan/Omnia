import Foundation

/// Follows the system's Low Power Mode for the setting of the same name.
@MainActor
@Observable
final class LowPowerMonitor {
    static let shared = LowPowerMonitor()

    private(set) var isSystemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSystemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    func isActive(_ mode: LowPowerMode) -> Bool {
        switch mode {
        case .automatic: isSystemLowPower
        case .on: true
        case .off: false
        }
    }
}
