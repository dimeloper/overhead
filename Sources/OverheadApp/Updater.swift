import AppKit
import Sparkle

/// Updates through Sparkle. The feed is `SUFeedURL` in Info.plist: `appcast.xml` on the latest GitHub release, which
/// `scripts/publish-release.sh` generates and signs. Sparkle installs an update only if its EdDSA signature matches
/// `SUPublicEDKey`.
///
/// Overhead lives in the menu bar, so a scheduled check that finds an update doesn't open a window over your work:
/// it sets `available`, the popover shows a row, and Sparkle's window opens when you click it.
@MainActor
final class Updater: NSObject, ObservableObject {
    /// The version a scheduled check found, until you install or skip it.
    @Published private(set) var available: String?
    @Published private(set) var isRunning = false

    private var controller: SPUStandardUpdaterController?

    /// Release builds with a feed. Debug builds and the demo never check, so running from source stays offline.
    static var isEnabled: Bool {
        #if DEBUG
        return false
        #else
        return Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        #endif
    }

    var automaticChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func start() {
        guard Self.isEnabled, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        isRunning = true
    }

    /// You asked: Sparkle's window opens, with the update a scheduled check already found, if there is one.
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

extension Updater: SPUUpdaterDelegate {
    /// `defaults write com.dimeloper.overhead updateFeedURL <url>` points a release build at another feed, to rehearse
    /// an update before it's published. The update must still be signed with the key in `SUPublicEDKey`.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "updateFeedURL")
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Only when the check ran right at launch, which is when you'd expect a window anyway.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            if !handleShowingUpdate { available = version }
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { available = nil }
    }
}
