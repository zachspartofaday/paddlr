import AppKit
import Combine
import Darwin
import SwiftUI

private struct MenuBarLaunchOptions {
    private static let diagnosticUIEnvironmentKey = "PADDLR_DIAGNOSTIC_UI"
    private static let legacyDiagnosticUIEnvironmentKey = "ELITEMAPPER_DIAGNOSTIC_UI"
    private static let diagnosticUIArgument = "--diagnostic-ui"

    let showsDiagnosticHelperText: Bool

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) {
        let isEnvironmentEnabled = [
            environment[Self.diagnosticUIEnvironmentKey],
            environment[Self.legacyDiagnosticUIEnvironmentKey]
        ].contains { value in
            value.map(Self.isEnabledValue) == true
        }
        let isArgumentEnabled = arguments.dropFirst().contains(Self.diagnosticUIArgument)

        showsDiagnosticHelperText = isEnvironmentEnabled || isArgumentEnabled
    }

    private static func isEnabledValue(_ value: String) -> Bool {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes", "on"].contains(normalizedValue)
    }
}

final class SingleInstanceLock {
    private let fileDescriptor: CInt

    init?(name: String) {
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return nil
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }

        fileDescriptor = descriptor
        let pidText = "\(ProcessInfo.processInfo.processIdentifier)\n"
        ftruncate(fileDescriptor, 0)
        _ = pidText.withCString { pointer in
            write(fileDescriptor, pointer, strlen(pointer))
        }
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private enum PopoverLayout {
        static let fallbackSize = MappingPanelView.preferredContentSize
        static let minimumHeight: CGFloat = 240
        static let screenMargin: CGFloat = 28
    }

    private enum StatusItemIcon {
        static let disabledSymbolName = "gamecontroller.circle"
        static let enabledSymbolName = "gamecontroller.circle.fill"
        static let fallbackSymbolName = "gamecontroller"
        static let pointSize: CGFloat = 18
        static let canvasSize = NSSize(width: 22, height: 22)
        static let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    }

    private let model = MenuBarMapperModel()
    private let popover = NSPopover()
    private let showsDiagnosticHelperText: Bool
    private var statusItem: NSStatusItem?
    private var statusItemStateCancellable: AnyCancellable?
    private var statusItemImageCache: [MenuBarStatusItemState: NSImage] = [:]
    private var latestContentSize = PopoverLayout.fallbackSize

    init(showsDiagnosticHelperText: Bool) {
        self.showsDiagnosticHelperText = showsDiagnosticHelperText
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "Paddlr paddle mappings"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItemStateCancellable = model.$statusItemState
            .removeDuplicates()
            .sink { [weak self] state in
                self?.updateStatusItemAppearance(state)
            }
        updateStatusItemAppearance(model.statusItemState)

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = latestContentSize
        popover.contentViewController = NSHostingController(
            rootView: MappingPanelView(
                model: model,
                showsDiagnosticHelperText: showsDiagnosticHelperText
            ) { [weak self] size in
                self?.resizePopover(to: size)
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model.noteApplicationDidResignActive()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let prompt = model.consumePermissionRestartPromptAfterActivation() else {
            return
        }

        showPermissionRestartPrompt(prompt)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPopoverVisible(false)
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        let event = NSApp.currentEvent
        let isControlClick = event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true
        if event?.type == .rightMouseUp || isControlClick {
            showStatusMenu()
        } else {
            togglePopover(sender)
        }
    }

    @objc private func quitApplication(_ sender: AnyObject?) {
        NSApplication.shared.terminate(sender)
    }

    private func showPermissionRestartPrompt(_ prompt: PermissionRestartPrompt) {
        let alert = NSAlert()
        alert.messageText = prompt.messageText
        alert.informativeText = prompt.informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit Paddlr")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
            model.setPopoverVisible(false)
        } else {
            showPopover()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else {
            return
        }

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Paddlr", action: #selector(quitApplication(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: quitItem, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    private func updateStatusItemAppearance(_ state: MenuBarStatusItemState) {
        guard let button = statusItem?.button else {
            return
        }

        button.contentTintColor = nil
        if let image = statusItemImage(for: state) {
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = nil
            button.title = "🎮"
        }
        button.toolTip = state.isEnabledForCurrentApplication
            ? "Paddlr paddle mappings enabled for this app"
            : "Paddlr paddle mappings disabled for this app"
    }

    private func statusItemImage(for state: MenuBarStatusItemState) -> NSImage? {
        if let cachedImage = statusItemImageCache[state] {
            return cachedImage
        }

        let symbolName = state.isEnabledForCurrentApplication ? StatusItemIcon.enabledSymbolName : StatusItemIcon.disabledSymbolName
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Paddlr"
        ) ?? NSImage(systemSymbolName: StatusItemIcon.fallbackSymbolName, accessibilityDescription: "Paddlr") else {
            return nil
        }

        let configuredImage = image.withSymbolConfiguration(StatusItemIcon.configuration) ?? image
        let statusColor: NSColor = state.isControllerConnected ? .controlAccentColor : .systemRed
        let renderedImage: NSImage

        if #available(macOS 12.0, *) {
            let paletteConfiguration = StatusItemIcon.configuration.applying(
                NSImage.SymbolConfiguration(paletteColors: [.white, statusColor])
            )
            let paletteImage = image.withSymbolConfiguration(paletteConfiguration) ?? configuredImage
            paletteImage.isTemplate = false
            renderedImage = paletteImage.normalizedStatusItemImage(canvasSize: StatusItemIcon.canvasSize)
        } else {
            renderedImage = configuredImage.tinted(with: statusColor).normalizedStatusItemImage(canvasSize: StatusItemIcon.canvasSize)
        }

        statusItemImageCache[state] = renderedImage
        return renderedImage
    }

    private func showPopover() {
        guard let button = statusItem?.button else {
            return
        }

        model.setPopoverVisible(true)
        refreshContentSizeFromFittingView(for: button)
        popover.contentSize = boundedPopoverSize(latestContentSize, for: button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func refreshContentSizeFromFittingView(for button: NSStatusBarButton?) {
        guard let view = popover.contentViewController?.view else {
            return
        }

        view.layoutSubtreeIfNeeded()
        let fittingSize = view.fittingSize
        guard fittingSize.height > 0 else {
            return
        }

        latestContentSize = boundedPopoverSize(
            NSSize(width: PopoverLayout.fallbackSize.width, height: ceil(fittingSize.height)),
            for: button
        )
    }

    private func resizePopover(to contentSize: NSSize) {
        let boundedSize = boundedPopoverSize(contentSize, for: statusItem?.button)
        guard abs(latestContentSize.width - boundedSize.width) > 0.5 || abs(latestContentSize.height - boundedSize.height) > 0.5 else {
            return
        }

        latestContentSize = boundedSize
        if popover.isShown {
            popover.contentSize = boundedSize
        }
    }

    private func boundedPopoverSize(_ contentSize: NSSize, for button: NSStatusBarButton?) -> NSSize {
        let fallbackSize = PopoverLayout.fallbackSize
        let rawHeight = contentSize.height > 0 ? contentSize.height : fallbackSize.height
        let visibleFrame = button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let maximumHeight = max(
            PopoverLayout.minimumHeight,
            (visibleFrame?.height ?? fallbackSize.height) - PopoverLayout.screenMargin
        )

        return NSSize(
            width: fallbackSize.width,
            height: min(max(rawHeight, PopoverLayout.minimumHeight), maximumHeight)
        )
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let targetSize = size
        let rect = NSRect(origin: .zero, size: targetSize)
        let sourceRect = NSRect(origin: .zero, size: targetSize)
        let sourceImage = (copy() as? NSImage) ?? self
        sourceImage.isTemplate = false
        sourceImage.size = targetSize

        let tintedImage = NSImage(size: targetSize)
        tintedImage.lockFocus()
        sourceImage.draw(
            in: rect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        color.set()
        rect.fill(using: .sourceAtop)
        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        return tintedImage
    }

    func normalizedStatusItemImage(canvasSize: NSSize) -> NSImage {
        let sourceImage = (copy() as? NSImage) ?? self
        sourceImage.isTemplate = false
        sourceImage.size = size

        let scale = min(canvasSize.width / max(size.width, 1), canvasSize.height / max(size.height, 1))
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        let drawRect = NSRect(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        let normalizedImage = NSImage(size: canvasSize)
        normalizedImage.lockFocus()
        sourceImage.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        normalizedImage.unlockFocus()
        normalizedImage.isTemplate = false
        return normalizedImage
    }
}

guard let singleInstanceLock = SingleInstanceLock(name: "EliteMapperMenuBar") else {
    fputs("Paddlr is already running, or a legacy EliteMapperMenuBar instance is still running.\n", stderr)
    exit(EXIT_FAILURE)
}

private let launchOptions = MenuBarLaunchOptions()
let app = NSApplication.shared
let delegate = AppDelegate(showsDiagnosticHelperText: launchOptions.showsDiagnosticHelperText)
app.delegate = delegate
withExtendedLifetime(singleInstanceLock) {
    app.run()
}
