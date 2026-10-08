import AppKit
import ServiceManagement

/// "Open at Login" through the system login-items API, plus detection of a login launch so the
/// app can start without putting a window on screen.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// True while handling the launch Apple event of a login-item launch.
    static var launchEventIsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication),
              let property = event.paramDescriptor(forKeyword: AEKeyword(fourCharCode("prdt"))) else { return false }
        return property.enumCodeValue == fourCharCode("lgit")
    }

    private static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
