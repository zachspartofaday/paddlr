import AppKit
import Foundation

struct FrontmostApplicationInfo: Equatable {
    var bundleIdentifier: String?
    var name: String
    var processIdentifier: pid_t

    var displayName: String {
        name.isEmpty ? "Unknown App" : name
    }

    var ruleKey: String? {
        bundleIdentifier
    }
}

final class FrontmostAppMonitor {
    private let onChange: (FrontmostApplicationInfo) -> Void
    private var observer: NSObjectProtocol?

    init(onChange: @escaping (FrontmostApplicationInfo) -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        if let current = Self.currentExternalApplicationInfo() {
            onChange(current)
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let info = Self.info(for: app),
                !Self.isCurrentProcess(info)
            else {
                return
            }

            self?.onChange(info)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private static func currentExternalApplicationInfo() -> FrontmostApplicationInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        guard let info = info(for: app), !isCurrentProcess(info) else {
            return nil
        }

        return info
    }

    private static func info(for app: NSRunningApplication) -> FrontmostApplicationInfo? {
        FrontmostApplicationInfo(
            bundleIdentifier: app.bundleIdentifier,
            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown App",
            processIdentifier: app.processIdentifier
        )
    }

    private static func isCurrentProcess(_ info: FrontmostApplicationInfo) -> Bool {
        info.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}
