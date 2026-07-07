import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService. Registration only works from a real
/// .app bundle — from a bare `swift run` binary it throws and logs.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("DropTerm: launch-at-login change failed: %@", error.localizedDescription)
        }
    }
}
