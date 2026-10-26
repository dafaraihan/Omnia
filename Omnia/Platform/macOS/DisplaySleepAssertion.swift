#if os(macOS)
import Foundation
import IOKit.pwr_mgt

/// Keeps the display awake while media plays. AVPlayer did this on its own;
/// libmpv doesn't, so without it the Mac's "turn display off" timer blanks
/// the screen mid-movie. Held only while playing, so a paused or stopped
/// player lets the Mac sleep as usual.
@MainActor
final class DisplaySleepAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var isHeld = false

    func update(isPlaying: Bool) {
        if isPlaying { acquire() } else { release() }
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHeld = false
    }

    private func acquire() {
        guard !isHeld else { return }
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Omnia is playing media" as CFString,
            &assertionID
        )
        isHeld = status == kIOReturnSuccess
    }
}
#endif
