import Darwin
import Foundation
import GameController
import PaddlrCore

final class GameControllerDiagnostics {
    private var observers: [NSObjectProtocol] = []
    private var registeredControllerIDs = Set<ObjectIdentifier>()
    private let hidPaddleMonitor = HIDPaddleMonitor { message in
        print("[IOHID] \(message)")
        fflush(stdout)
    }

    func start() {
        print("Paddlr Input Diagnostics")
        print("Primary target: macOS 26 Tahoe")
        print("This tool dumps every GameController input key macOS exposes and logs raw IOHID paddle fallback events.")
        print("Press controller buttons/paddles while it runs. Press Control-C to exit.")
        print("")
        fflush(stdout)

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
                guard let controller = notification.object as? GCController else { return }
                self?.inspect(controller: controller)
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { notification in
                guard let controller = notification.object as? GCController else { return }
                print("Controller disconnected: \(controller.vendorName ?? "Unknown controller")")
                fflush(stdout)
            }
        )

        let controllers = GCController.controllers()
        if controllers.isEmpty {
            print("No controllers connected yet.")
            fflush(stdout)
        } else {
            controllers.forEach(inspect(controller:))
        }

        GCController.startWirelessControllerDiscovery {
            print("[GameController] Wireless discovery callback completed.")
            fflush(stdout)
        }

        hidPaddleMonitor.start()
    }

    private func inspect(controller: GCController) {
        let controllerID = ObjectIdentifier(controller)
        guard registeredControllerIDs.insert(controllerID).inserted else { return }

        print("=== Controller ===")
        print("Vendor name: \(controller.vendorName ?? "Unknown controller")")
        if #available(macOS 11.0, *) {
            print("Product category: \(controller.productCategory)")
        }
        print("Has extendedGamepad: \(controller.extendedGamepad != nil)")
        print("Has microGamepad: \(controller.microGamepad != nil)")
        print("Has motion: \(controller.motion != nil)")
        print("")

        let profile = controller.physicalInputProfile
        dumpKeys(title: "Buttons", keys: profile.buttons.keys)
        dumpKeys(title: "Axes", keys: profile.axes.keys)
        dumpKeys(title: "Direction pads", keys: profile.dpads.keys)
        dumpKeys(title: "Elements", keys: profile.elements.keys)

        print("Expected Xbox Elite paddle constants:")
        for paddle in Paddle.allCases {
            let key = paddle.gameControllerInputName
            let present = profile.buttons[key] == nil ? "missing" : "present"
            print("- \(paddle.consoleName): '\(key)' -> \(present)")
        }
        print("")

        registerLiveHandlers(profile: profile)
        fflush(stdout)
    }

    private func dumpKeys<T: Collection>(title: String, keys: T) where T.Element == String {
        let sortedKeys = keys.sorted()
        print("=== \(title) (\(sortedKeys.count)) ===")
        if sortedKeys.isEmpty {
            print("(none)")
        } else {
            for key in sortedKeys {
                print("- \(key)")
            }
        }
        print("")
    }

    private func registerLiveHandlers(profile: GCPhysicalInputProfile) {
        for (name, button) in profile.buttons {
            button.pressedChangedHandler = { _, value, pressed in
                let state = pressed ? "pressed" : "released"
                print("[GameController] button[\(name)] \(state) value=\(String(format: "%.3f", value))")
                fflush(stdout)
            }
        }

        for (name, axis) in profile.axes {
            axis.valueChangedHandler = { _, value in
                print("[GameController] axis[\(name)] value=\(String(format: "%.3f", value))")
                fflush(stdout)
            }
        }

        for (name, dpad) in profile.dpads {
            dpad.valueChangedHandler = { _, xValue, yValue in
                print("[GameController] dpad[\(name)] x=\(String(format: "%.3f", xValue)) y=\(String(format: "%.3f", yValue))")
                fflush(stdout)
            }
        }
    }
}

let diagnostics = GameControllerDiagnostics()
diagnostics.start()
RunLoop.main.run()
