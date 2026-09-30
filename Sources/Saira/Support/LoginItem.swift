import AppKit
import Observation
import ServiceManagement

/// "Start at login", via the modern `SMAppService` API — no helper app, no LaunchAgent plist.
///
/// On by default: the first time the app runs it registers itself, so it's ready whenever the
/// Mac starts. That happens once — switch it off and it stays off.
///
/// macOS is the source of truth, not a stored flag: the user can also remove the app in
/// System Settings ▸ General ▸ Login Items, and the switch has to reflect that. `refresh()`
/// re-reads it whenever the app comes back to the front.
///
/// macOS only honours this for an app in a stable location, which is one more reason
/// `make install` copies the app into /Applications.
@MainActor
@Observable
final class LoginItem {
    static let shared = LoginItem()

    private(set) var isEnabled = false
    /// Registered, but the user has to allow it in System Settings ▸ General ▸ Login Items.
    private(set) var needsApproval = false
    private(set) var lastError: String?

    private static let didSetUpKey = "loginItemSetUp"
    private static let registeredPathKey = "loginItemRegisteredPath"

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { LoginItem.shared.refresh() }
        }
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "Couldn't change it: \(error.localizedDescription)"
            Log.app.error("login item: \(error.localizedDescription)")
        }
        refresh()
    }

    /// Turns "Start at login" on the first time the app ever runs — and re-registers it if
    /// the app has moved or been renamed since, so macOS launches *this* copy at login rather
    /// than a path that no longer exists.
    func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        let path = Bundle.main.bundlePath
        defer { if isEnabled { defaults.set(path, forKey: Self.registeredPathKey) } }

        guard defaults.bool(forKey: Self.didSetUpKey) else {
            defaults.set(true, forKey: Self.didSetUpKey)
            if !isEnabled { setEnabled(true) }
            Log.app.info("login item set up on first launch — enabled: \(self.isEnabled, privacy: .public)")
            return
        }

        let registered = defaults.string(forKey: Self.registeredPathKey)
        guard isEnabled, registered != path else { return }
        try? SMAppService.mainApp.unregister()
        setEnabled(true)
        Log.app.info("login item re-registered for \(path, privacy: .public) — enabled: \(self.isEnabled, privacy: .public)")
    }

    var statusText: String {
        if let lastError { return lastError }
        if needsApproval { return "Almost — allow it in System Settings ▸ General ▸ Login Items." }
        return isEnabled
            ? "On. Saira opens by itself whenever your Mac starts or you log in."
            : "Off. You'll open Saira yourself after a restart."
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
