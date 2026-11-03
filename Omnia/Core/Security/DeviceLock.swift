import Foundation
import LocalAuthentication

/// Face ID, Touch ID or the device passcode in front of Settings and profile
/// switching. Kept on this device only: it isn't synced, since each device has
/// its own biometrics and its own idea of who holds it.
@MainActor
@Observable
final class DeviceLock {
    static let shared = DeviceLock()

    private static let settingsKey = "device-lock-settings"
    private static let profilesKey = "device-lock-profiles"

    private(set) var locksSettings = UserDefaults.standard.bool(forKey: settingsKey)
    private(set) var locksProfiles = UserDefaults.standard.bool(forKey: profilesKey)
    private(set) var isSettingsUnlocked = false

    /// "Face ID", "Touch ID", or the passcode when neither is set up.
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
    }

    func unlockSettings() async {
        if await authenticate(reason: "Unlock Settings") { isSettingsUnlocked = true }
    }

    func relock() {
        isSettingsUnlocked = false
    }

    /// Turning a lock on or off is itself protected.
    func setLocksSettings(_ enabled: Bool) async {
        guard await authenticate(reason: enabled ? "Lock Settings" : "Stop locking Settings") else { return }
        locksSettings = enabled
        isSettingsUnlocked = enabled
        UserDefaults.standard.set(enabled, forKey: Self.settingsKey)
    }

    func setLocksProfiles(_ enabled: Bool) async {
        guard await authenticate(reason: enabled ? "Lock profile switching" : "Stop locking profile switching") else { return }
        locksProfiles = enabled
        UserDefaults.standard.set(enabled, forKey: Self.profilesKey)
    }
}
