import Darwin
import Foundation
import IOKit.hid

func flushPrint(_ message: String = "") {
    print(message)
    fflush(stdout)
}

func hex(_ value: Int) -> String {
    "0x" + String(value, radix: 16, uppercase: false)
}

func hidProperty(_ device: IOHIDDevice, _ key: CFString) -> String {
    guard let property = IOHIDDeviceGetProperty(device, key) else {
        return "(missing)"
    }
    return String(describing: property)
}

func elementTypeName(_ type: IOHIDElementType) -> String {
    switch type {
    case kIOHIDElementTypeInput_Misc:
        return "input-misc"
    case kIOHIDElementTypeInput_Button:
        return "input-button"
    case kIOHIDElementTypeInput_Axis:
        return "input-axis"
    case kIOHIDElementTypeInput_ScanCodes:
        return "input-scancodes"
    case kIOHIDElementTypeOutput:
        return "output"
    case kIOHIDElementTypeFeature:
        return "feature"
    case kIOHIDElementTypeCollection:
        return "collection"
    default:
        return "type-\(type.rawValue)"
    }
}

func isInputElement(_ type: IOHIDElementType) -> Bool {
    type == kIOHIDElementTypeInput_Misc ||
        type == kIOHIDElementTypeInput_Button ||
        type == kIOHIDElementTypeInput_Axis ||
        type == kIOHIDElementTypeInput_ScanCodes
}

func describeDevice(_ device: IOHIDDevice) {
    flushPrint("=== IOHID Device ===")
    flushPrint("Product: \(hidProperty(device, kIOHIDProductKey as CFString))")
    flushPrint("Manufacturer: \(hidProperty(device, kIOHIDManufacturerKey as CFString))")
    flushPrint("Transport: \(hidProperty(device, kIOHIDTransportKey as CFString))")
    flushPrint("VendorID: \(hidProperty(device, kIOHIDVendorIDKey as CFString))")
    flushPrint("ProductID: \(hidProperty(device, kIOHIDProductIDKey as CFString))")
    flushPrint("PrimaryUsagePage: \(hidProperty(device, kIOHIDPrimaryUsagePageKey as CFString))")
    flushPrint("PrimaryUsage: \(hidProperty(device, kIOHIDPrimaryUsageKey as CFString))")
    flushPrint("")

    guard let rawElements = IOHIDDeviceCopyMatchingElements(
        device,
        nil,
        IOOptionBits(kIOHIDOptionsTypeNone)
    ) as? [IOHIDElement] else {
        flushPrint("No HID elements returned.")
        return
    }

    let inputElements = rawElements.filter { isInputElement(IOHIDElementGetType($0)) }
    flushPrint("=== Input elements (\(inputElements.count)) ===")

    for element in inputElements.sorted(by: { lhs, rhs in
        let lhsKey = (
            Int(IOHIDElementGetReportID(lhs)),
            Int(IOHIDElementGetUsagePage(lhs)),
            Int(IOHIDElementGetUsage(lhs)),
            Int(IOHIDElementGetCookie(lhs))
        )
        let rhsKey = (
            Int(IOHIDElementGetReportID(rhs)),
            Int(IOHIDElementGetUsagePage(rhs)),
            Int(IOHIDElementGetUsage(rhs)),
            Int(IOHIDElementGetCookie(rhs))
        )
        if lhsKey.0 != rhsKey.0 { return lhsKey.0 < rhsKey.0 }
        if lhsKey.1 != rhsKey.1 { return lhsKey.1 < rhsKey.1 }
        if lhsKey.2 != rhsKey.2 { return lhsKey.2 < rhsKey.2 }
        return lhsKey.3 < rhsKey.3
    }) {
        let type = IOHIDElementGetType(element)
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let reportID = Int(IOHIDElementGetReportID(element))
        let cookie = Int(IOHIDElementGetCookie(element))
        let min = IOHIDElementGetLogicalMin(element)
        let max = IOHIDElementGetLogicalMax(element)
        let marker = (reportID == 1 && usagePage == 0x0C && usage == 0x81) ? " likely-paddle-mask" : ""
        flushPrint("report=\(reportID) cookie=\(cookie) type=\(elementTypeName(type)) usagePage=\(hex(usagePage)) usage=\(usage) logical=[\(min),\(max)]\(marker)")
    }
    flushPrint("")
}

let inputValueCallback: IOHIDValueCallback = { _, result, _, value in
    guard result == kIOReturnSuccess else { return }

    let element = IOHIDValueGetElement(value)
    let type = IOHIDElementGetType(element)
    guard isInputElement(type) else { return }

    let usagePage = Int(IOHIDElementGetUsagePage(element))
    let usage = Int(IOHIDElementGetUsage(element))
    let reportID = Int(IOHIDElementGetReportID(element))
    let cookie = Int(IOHIDElementGetCookie(element))
    let intValue = IOHIDValueGetIntegerValue(value)

    let marker = (reportID == 1 && usagePage == 0x0C && usage == 0x81) ? " likely-paddle-mask" : ""
    flushPrint("value report=\(reportID) cookie=\(cookie) type=\(elementTypeName(type)) usagePage=\(hex(usagePage)) usage=\(usage) value=\(intValue)\(marker)")
}

flushPrint("Paddlr IOHID Probe")
flushPrint("This probes raw HID devices from Microsoft (VendorID 0x045e).")
flushPrint("Press controller buttons/paddles while it runs. Press Control-C to exit.")
flushPrint("")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: 0x045E,
    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_GamePad
]

IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
if devices.isEmpty {
    flushPrint("No matching Microsoft gamepad HID devices found.")
} else {
    for device in devices {
        describeDevice(device)
    }
}

IOHIDManagerRegisterInputValueCallback(manager, inputValueCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openStatus == kIOReturnSuccess {
    flushPrint("Listening for live HID input values...")
    RunLoop.main.run()
} else {
    fputs("Live IOHID monitoring unavailable. IOHIDManagerOpen returned \(openStatus).\n", stderr)
    fputs("If static device/elements are listed above, the device exists but macOS denied raw live input access to this process. Grant Terminal/Input Monitoring permission or use USB for the next probe.\n", stderr)
    exit(EXIT_SUCCESS)
}
