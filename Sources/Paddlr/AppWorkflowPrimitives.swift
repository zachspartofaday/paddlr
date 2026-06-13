import Foundation
import PaddlrCore

struct RecentEventLogModel {
    private var eventBuffer: [String] = []
    private var isPublishingEnabled = false
    private let maxEvents: Int
    private let timestampFormatter: DateFormatter

    var isPublishing: Bool {
        isPublishingEnabled
    }

    init(maxEvents: Int) {
        self.maxEvents = maxEvents
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        self.timestampFormatter = formatter
    }

    mutating func setPublishingEnabled(_ isEnabled: Bool) -> [String]? {
        guard isPublishingEnabled != isEnabled else {
            return nil
        }

        isPublishingEnabled = isEnabled
        return isEnabled ? eventBuffer : nil
    }

    mutating func append(_ message: String, date: Date = Date()) -> [String]? {
        let timestamp = timestampFormatter.string(from: date)
        eventBuffer.insert("[\(timestamp)] \(message)", at: 0)

        if eventBuffer.count > maxEvents {
            eventBuffer.removeLast(eventBuffer.count - maxEvents)
        }

        return isPublishingEnabled ? eventBuffer : nil
    }
}

struct MonitorStatusPresentation: Equatable {
    var monitorStatus: String
    var paddleDeviceStatus: HIDPaddleDeviceStatus?
}

struct MonitorStatusPresenter {
    func presentation(
        for message: String,
        paddleDeviceStatus: HIDPaddleDeviceStatus
    ) -> MonitorStatusPresentation? {
        if message.contains("Raw IOHID paddle monitor listening") {
            if paddleDeviceStatus.connectedDeviceCount > 1 {
                return MonitorStatusPresentation(
                    monitorStatus: "Listening to \(paddleDeviceStatus.connectedDeviceCount) Xbox Elite controllers.",
                    paddleDeviceStatus: nil
                )
            } else if paddleDeviceStatus.isConnected {
                return MonitorStatusPresentation(
                    monitorStatus: "Listening for Xbox Elite paddle input.",
                    paddleDeviceStatus: nil
                )
            } else if paddleDeviceStatus.unsupportedControllerCount > 0 {
                return MonitorStatusPresentation(
                    monitorStatus: "Microsoft controller detected without Elite paddle input.",
                    paddleDeviceStatus: nil
                )
            }

            return MonitorStatusPresentation(
                monitorStatus: "Listening for Xbox Elite paddle input.",
                paddleDeviceStatus: nil
            )
        } else if message.contains("Raw HID paddle mask element found") {
            return MonitorStatusPresentation(monitorStatus: "Paddle mask detected.", paddleDeviceStatus: nil)
        } else if message.contains("Raw HID paddle mask element not found") {
            return MonitorStatusPresentation(
                monitorStatus: "Microsoft controller detected without Elite paddle input.",
                paddleDeviceStatus: nil
            )
        } else if message.contains("No Microsoft gamepad HID devices found") {
            return MonitorStatusPresentation(
                monitorStatus: "Waiting for a Microsoft gamepad.",
                paddleDeviceStatus: HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
            )
        } else if message.contains("unavailable") {
            return MonitorStatusPresentation(
                monitorStatus: "Raw IOHID monitor unavailable.",
                paddleDeviceStatus: HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
            )
        } else if message.contains("Starting raw IOHID paddle monitor") {
            return MonitorStatusPresentation(monitorStatus: "Starting raw IOHID monitor...", paddleDeviceStatus: nil)
        }

        return nil
    }
}

enum PermissionRestartPromptKind {
    case accessibility
    case controllerInputAccess
}

struct PermissionCoordinator {
    private var pendingPromptKind: PermissionRestartPromptKind?
    private var pendingPromptArmedAt: Date?
    private var requestObservedApplicationResignActive = false

    var hasPendingPrompt: Bool {
        pendingPromptKind != nil
    }

    mutating func armRestartPrompt(for kind: PermissionRestartPromptKind, now: Date = Date()) {
        pendingPromptKind = kind
        pendingPromptArmedAt = now
        requestObservedApplicationResignActive = false
    }

    mutating func noteApplicationDidResignActive() {
        if pendingPromptKind != nil {
            requestObservedApplicationResignActive = true
        }
    }

    mutating func consumeRestartPromptAfterActivation(now: Date = Date()) -> Bool {
        guard pendingPromptKind != nil else {
            return false
        }

        let elapsedSinceRequest = pendingPromptArmedAt.map { now.timeIntervalSince($0) } ?? 0
        guard requestObservedApplicationResignActive || elapsedSinceRequest > 2 else {
            return false
        }

        pendingPromptKind = nil
        pendingPromptArmedAt = nil
        requestObservedApplicationResignActive = false
        return true
    }
}
