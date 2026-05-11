import Darwin
import Foundation
import IOKit.hid

func flushPrint(_ message: String = "") {
    print(message)
    fflush(stdout)
}

func hidProperty(_ device: IOHIDDevice, _ key: CFString) -> String {
    guard let property = IOHIDDeviceGetProperty(device, key) else {
        return "(missing)"
    }
    return String(describing: property)
}

func hidIntProperty(_ device: IOHIDDevice, _ key: CFString, default defaultValue: Int) -> Int {
    guard let property = IOHIDDeviceGetProperty(device, key) else {
        return defaultValue
    }

    if let number = property as? NSNumber {
        return number.intValue
    }

    return defaultValue
}

func hexBytes(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

final class RawReportSession {
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let capacity: CFIndex
    private var lastReports: [UInt32: [UInt8]] = [:]

    init(device: IOHIDDevice) {
        self.device = device
        let maxInputReportSize = hidIntProperty(device, kIOHIDMaxInputReportSizeKey as CFString, default: 128)
        self.capacity = CFIndex(max(128, maxInputReportSize + 1))
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(capacity))
        self.buffer.initialize(repeating: 0, count: Int(capacity))
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deinitialize(count: Int(capacity))
        buffer.deallocate()
    }

    func start() {
        flushPrint("=== Raw report device ===")
        flushPrint("Product: \(hidProperty(device, kIOHIDProductKey as CFString))")
        flushPrint("Manufacturer: \(hidProperty(device, kIOHIDManufacturerKey as CFString))")
        flushPrint("Transport: \(hidProperty(device, kIOHIDTransportKey as CFString))")
        flushPrint("VendorID: \(hidProperty(device, kIOHIDVendorIDKey as CFString))")
        flushPrint("ProductID: \(hidProperty(device, kIOHIDProductIDKey as CFString))")
        flushPrint("MaxInputReportSize: \(hidIntProperty(device, kIOHIDMaxInputReportSizeKey as CFString, default: -1))")

        let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            flushPrint("Unable to open raw HID device: \(openStatus)")
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            RawReportSession.reportCallback,
            context
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        flushPrint("Listening for raw input reports...")
        flushPrint("")
    }

    private func handle(
        result: IOReturn,
        type: IOHIDReportType,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput else {
            return
        }

        let length = Int(reportLength)
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))

        // Avoid printing duplicate reports. USB reports often include a counter, so button actions
        // will still show up as changed reports while idle repeats are suppressed.
        if lastReports[reportID] == bytes {
            return
        }
        lastReports[reportID] = bytes

        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        flushPrint("raw t=\(timestamp) reportID=\(reportID) len=\(length) bytes=\(hexBytes(bytes))")
    }

    private static let reportCallback: IOHIDReportCallback = { context, result, _, type, reportID, report, reportLength in
        guard let context else {
            return
        }

        let session = Unmanaged<RawReportSession>.fromOpaque(context).takeUnretainedValue()
        session.handle(
            result: result,
            type: type,
            reportID: reportID,
            report: report,
            reportLength: reportLength
        )
    }
}

flushPrint("Paddlr Raw HID Report Probe")
flushPrint("This dumps changed raw input reports from Microsoft gamepads.")
flushPrint("Use it to decode USB packets when IOHID element values are packed into vendor reports.")
flushPrint("Press Control-C to exit.")
flushPrint("")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: 0x045E,
    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_GamePad
]

IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
guard !devices.isEmpty else {
    flushPrint("No matching Microsoft gamepad HID devices found.")
    exit(EXIT_SUCCESS)
}

var sessions: [RawReportSession] = []
for device in devices {
    let session = RawReportSession(device: device)
    sessions.append(session)
    session.start()
}

RunLoop.main.run()
