import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+) for "Open at login".
enum LoginItemHelper {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Errors are surfaced via `lastError`.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let svc = SMAppService.mainApp
        do {
            if enabled {
                if svc.status != .enabled { try svc.register() }
            } else {
                if svc.status == .enabled { try svc.unregister() }
            }
            lastError = nil
            return true
        } catch {
            lastError = error
            return false
        }
    }

    private(set) static var lastError: Error?
}
