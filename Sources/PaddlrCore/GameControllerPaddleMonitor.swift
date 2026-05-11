import Darwin
import Foundation
import GameController

/// Monitors connected GameController devices for Xbox Elite paddle button events.
public final class GameControllerPaddleMonitor {
    private var observers: [NSObjectProtocol] = []
    private var registeredControllerIDs = Set<ObjectIdentifier>()
    private let log: (String) -> Void

    public convenience init() {
        self.init(log: GameControllerPaddleMonitor.defaultLog(_:))
    }

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    private static func defaultLog(_ message: String) {
        print(message)
        fflush(stdout)
    }

    deinit {
        stop()
    }

    /// Starts controller discovery and registers handlers for already-connected controllers.
    public func start() {
        if Thread.isMainThread {
            startOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startOnMainThread()
            }
        }
    }

    /// Stops wireless discovery and removes notification observers.
    public func stop() {
        GCController.stopWirelessControllerDiscovery()

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        registeredControllerIDs.removeAll()
    }

    private func startOnMainThread() {
        guard observers.isEmpty else {
            return
        }

        log("Starting GameController discovery...")

        if #available(macOS 11.3, *) {
            GCController.shouldMonitorBackgroundEvents = true
        }

        let notificationCenter = NotificationCenter.default

        observers.append(
            notificationCenter.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else {
                    return
                }
                self?.register(controller: controller)
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else {
                    return
                }
                self?.handleDisconnect(controller: controller)
            }
        )

        let connectedControllers = GCController.controllers()
        if connectedControllers.isEmpty {
            log("No controllers connected yet. Connect an Xbox Elite Series 2 controller over Bluetooth, then press P1-P4.")
        } else {
            connectedControllers.forEach(register(controller:))
        }

        GCController.startWirelessControllerDiscovery { [weak self] in
            self?.log("Wireless controller discovery callback completed.")
        }
    }

    private func register(controller: GCController) {
        let controllerID = ObjectIdentifier(controller)
        guard registeredControllerIDs.insert(controllerID).inserted else {
            return
        }

        let controllerName = controller.vendorName ?? "Unknown controller"
        log("Controller connected: \(controllerName)")

        let profile = controller.physicalInputProfile
        var registeredPaddles: [Paddle] = []

        for paddle in Paddle.allCases {
            guard let button = profile.buttons[paddle.gameControllerInputName] else {
                log("\(paddle.consoleName) unavailable via GameController input '\(paddle.gameControllerInputName)'.")
                continue
            }

            registeredPaddles.append(paddle)
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                let state = pressed ? "pressed" : "released"
                self?.log("\(paddle.consoleName) \(state)")
            }
        }

        if registeredPaddles.isEmpty {
            log("No Xbox Elite paddle inputs were exposed for this controller via GameController.")
            log("Raw IOHID fallback may still expose the paddles as a bitmask.")
            log("Tip: use controller Profile 0/default profile if paddles appear as duplicate ABXY buttons.")
        } else {
            let names = registeredPaddles.map(\.consoleName).joined(separator: ", ")
            log("Registered paddle handlers: \(names)")
        }
    }

    private func handleDisconnect(controller: GCController) {
        registeredControllerIDs.remove(ObjectIdentifier(controller))
        let controllerName = controller.vendorName ?? "Unknown controller"
        log("Controller disconnected: \(controllerName)")
    }
}
