import Darwin
import Foundation
import IOKit.hid

public struct HIDPaddleControllerInfo: Equatable, Hashable, Sendable {
    public var identifier: String
    public var productName: String
    public var transport: String?
    public var vendorID: String?
    public var productID: String?

    public var isKnownXboxEliteSeries2: Bool {
        guard let normalizedProductID = Self.normalizedHexIdentifier(productID) else {
            return false
        }

        return Self.normalizedHexIdentifier(vendorID) == "45e" &&
            Self.knownXboxEliteSeries2ProductIDs.contains(normalizedProductID)
    }

    public init(
        identifier: String,
        productName: String,
        transport: String? = nil,
        vendorID: String? = nil,
        productID: String? = nil
    ) {
        self.identifier = identifier
        self.productName = productName
        self.transport = transport
        self.vendorID = vendorID
        self.productID = productID
    }

    private static let knownXboxEliteSeries2ProductIDs: Set<String> = ["b00", "b05", "b22"]

    private static func normalizedHexIdentifier(_ value: String?) -> String? {
        let normalized = value?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "")
            .drop { $0 == "0" }
            .description

        return normalized?.isEmpty == true ? "0" : normalized
    }
}

public struct HIDPaddleDeviceStatus: Equatable, Sendable {
    public var isConnected: Bool
    public var deviceName: String?
    public var connectedDeviceCount: Int
    public var controllers: [HIDPaddleControllerInfo]
    public var unsupportedControllerName: String?
    public var unsupportedControllerCount: Int
    public var unsupportedControllers: [HIDPaddleControllerInfo]

    public init(
        isConnected: Bool,
        deviceName: String?,
        connectedDeviceCount: Int = 0,
        controllers: [HIDPaddleControllerInfo] = [],
        unsupportedControllerName: String? = nil,
        unsupportedControllerCount: Int = 0,
        unsupportedControllers: [HIDPaddleControllerInfo] = []
    ) {
        self.isConnected = isConnected
        self.deviceName = deviceName
        self.controllers = controllers
        self.connectedDeviceCount = max(connectedDeviceCount, controllers.count, isConnected ? 1 : 0)
        self.unsupportedControllers = unsupportedControllers
        self.unsupportedControllerName = unsupportedControllerName ?? unsupportedControllers.first?.productName
        self.unsupportedControllerCount = max(
            unsupportedControllerCount,
            unsupportedControllers.count,
            self.unsupportedControllerName == nil ? 0 : 1
        )
    }
}

/// Monitors Xbox Elite paddle state through raw IOHID values when GameController does not expose paddles.
public final class HIDPaddleMonitor {
    public static func isInputMonitoringTrusted(prompt: Bool) -> Bool {
        if prompt {
            return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private enum Constants {
        static let microsoftVendorID = 0x045E
        static let genericDesktopGamePadUsagePage = kHIDPage_GenericDesktop
        static let genericDesktopGamePadUsage = kHIDUsage_GD_GamePad

        /// Observed on Xbox Elite Series 2 over Bluetooth LE on macOS 26 Tahoe.
        /// The value is a bitmask: P1=0x01, P2=0x02, P3=0x04, P4=0x08.
        static let bluetoothPaddleMaskUsagePage = 0x0C
        static let bluetoothPaddleMaskUsage = 0x81
        static let bluetoothPaddleMaskReportID = 1
    }

    private enum PaddleInputElementKind {
        case bluetoothPaddleMask

        var logDescription: String {
            "Bluetooth paddle mask element found: usagePage=0x0c usage=0x81 report=1"
        }
    }

    private struct DetectedPaddleDevice: Equatable {
        var runtimeID: UInt
        var info: HIDPaddleControllerInfo
        var discoveryOrder: Int
    }

    private struct DetectedPaddleDevices: Equatable {
        var devices: [DetectedPaddleDevice]
        var unsupportedDevices: [DetectedPaddleDevice] = []

        var deviceIDs: Set<UInt> {
            Set(devices.map(\.runtimeID))
        }

        var status: HIDPaddleDeviceStatus {
            let sortedControllers = Self.sortedControllerInfo(from: devices)
            let sortedUnsupportedControllers = Self.sortedControllerInfo(from: unsupportedDevices)
            let primaryDeviceName = sortedControllers.first?.productName
            return HIDPaddleDeviceStatus(
                isConnected: !sortedControllers.isEmpty,
                deviceName: primaryDeviceName,
                connectedDeviceCount: sortedControllers.count,
                controllers: sortedControllers,
                unsupportedControllerName: sortedUnsupportedControllers.first?.productName,
                unsupportedControllerCount: sortedUnsupportedControllers.count,
                unsupportedControllers: sortedUnsupportedControllers
            )
        }

        private static func sortedControllerInfo(from devices: [DetectedPaddleDevice]) -> [HIDPaddleControllerInfo] {
            devices.sorted {
                if $0.discoveryOrder != $1.discoveryOrder {
                    return $0.discoveryOrder < $1.discoveryOrder
                }

                if $0.info.productName == $1.info.productName {
                    return $0.info.identifier < $1.info.identifier
                }
                return $0.info.productName.localizedCaseInsensitiveCompare($1.info.productName) == .orderedAscending
            }
            .map(\.info)
        }
    }

    private let manager: IOHIDManager
    private let log: (String) -> Void
    private let onDeviceStatusChange: ((HIDPaddleDeviceStatus) -> Void)?
    private let onPaddleChange: ((Paddle, Bool) -> Void)?
    private let onControllerPaddleChange: ((HIDPaddleControllerInfo, Paddle, Bool) -> Void)?
    private var isStarted = false
    private var aggregatePaddleMask = 0
    private var paddleMasksByDeviceID: [UInt: Int] = [:]
    private var controllerDiscoveryOrderByIdentifier: [String: Int] = [:]
    private var nextControllerDiscoveryOrder = 0
    private var lastDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)

    public convenience init() {
        self.init(log: HIDPaddleMonitor.defaultLog(_:))
    }

    public convenience init(log: @escaping (String) -> Void) {
        self.init(log: log, onDeviceStatusChange: nil, onPaddleChange: nil)
    }

    public convenience init(
        log: @escaping (String) -> Void,
        onPaddleChange: ((Paddle, Bool) -> Void)?
    ) {
        self.init(log: log, onDeviceStatusChange: nil, onPaddleChange: onPaddleChange)
    }

    public init(
        log: @escaping (String) -> Void,
        onDeviceStatusChange: ((HIDPaddleDeviceStatus) -> Void)?,
        onPaddleChange: ((Paddle, Bool) -> Void)?,
        onControllerPaddleChange: ((HIDPaddleControllerInfo, Paddle, Bool) -> Void)? = nil
    ) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.log = log
        self.onDeviceStatusChange = onDeviceStatusChange
        self.onPaddleChange = onPaddleChange
        self.onControllerPaddleChange = onControllerPaddleChange
    }

    deinit {
        stop()
    }

    /// Starts monitoring Microsoft gamepad HID devices.
    public func start() {
        if Thread.isMainThread {
            startOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startOnMainThread()
            }
        }
    }

    /// Stops monitoring and closes the HID manager.
    public func stop() {
        guard isStarted else {
            return
        }

        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isStarted = false
        aggregatePaddleMask = 0
        paddleMasksByDeviceID.removeAll()
        controllerDiscoveryOrderByIdentifier.removeAll()
        nextControllerDiscoveryOrder = 0
        lastDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
    }

    /// Rechecks the currently connected matching HID devices and emits a status change when needed.
    public func pollDeviceStatus() {
        if Thread.isMainThread {
            pollDeviceStatusOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.pollDeviceStatusOnMainThread()
            }
        }
    }

    private func startOnMainThread() {
        guard !isStarted else {
            return
        }

        log("Starting raw IOHID paddle monitor...")

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Constants.microsoftVendorID,
            kIOHIDDeviceUsagePageKey as String: Constants.genericDesktopGamePadUsagePage,
            kIOHIDDeviceUsageKey as String: Constants.genericDesktopGamePadUsage
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let detectedPaddleDevices = detectPaddleDevices(logDevices: true)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, HIDPaddleMonitor.inputValueCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openStatus == kIOReturnSuccess {
            isStarted = true
            pruneTrackedDeviceMasks(to: detectedPaddleDevices.deviceIDs)
            updateDeviceStatus(detectedPaddleDevices.status, notifyWhenUnchanged: true)
            log("Raw IOHID paddle monitor listening.")
        } else {
            updateDeviceStatus(HIDPaddleDeviceStatus(isConnected: false, deviceName: nil), notifyWhenUnchanged: true)
            log("Raw IOHID paddle monitor unavailable: IOHIDManagerOpen returned \(openStatus).")
            log("If needed, grant Paddlr Input Monitoring permission and try again.")
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }
    }

    private func pollDeviceStatusOnMainThread() {
        guard isStarted else {
            return
        }

        let detectedPaddleDevices = detectPaddleDevices(logDevices: false)
        pruneTrackedDeviceMasks(to: detectedPaddleDevices.deviceIDs)
        updateDeviceStatus(detectedPaddleDevices.status, notifyWhenUnchanged: false)
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard let elementKind = paddleInputElementKind(for: element) else {
            return
        }

        let rawValue = IOHIDValueGetIntegerValue(value)
        let mask = paddleMask(from: rawValue, elementKind: elementKind)
        let device = IOHIDElementGetDevice(element)
        let deviceID = deviceIdentifier(device)
        let previousMask = paddleMasksByDeviceID[deviceID] ?? 0
        paddleMasksByDeviceID[deviceID] = mask
        let controller = controllerInfo(for: device)
        emitControllerPaddleChanges(controller: controller, previousMask: previousMask, newMask: mask)
        emitAggregatePaddleChanges(newMask: currentAggregatePaddleMask())
    }

    private func emitControllerPaddleChanges(
        controller: HIDPaddleControllerInfo,
        previousMask: Int,
        newMask: Int
    ) {
        let changedMask = previousMask ^ newMask
        guard changedMask != 0 else {
            return
        }

        for (paddle, bit) in paddleBits {
            guard changedMask & bit != 0 else {
                continue
            }

            let isPressed = (newMask & bit) != 0
            let state = isPressed ? "pressed" : "released"
            if onControllerPaddleChange != nil {
                log("\(controller.productName) \(paddle.consoleName) \(state)")
            }
            onControllerPaddleChange?(controller, paddle, isPressed)
        }
    }

    private func pruneTrackedDeviceMasks(to connectedDeviceIDs: Set<UInt>) {
        paddleMasksByDeviceID = paddleMasksByDeviceID.filter { connectedDeviceIDs.contains($0.key) }
        emitAggregatePaddleChanges(newMask: currentAggregatePaddleMask())
    }

    private func currentAggregatePaddleMask() -> Int {
        paddleMasksByDeviceID.values.reduce(0) { $0 | $1 }
    }

    private func emitAggregatePaddleChanges(newMask: Int) {
        let changedMask = aggregatePaddleMask ^ newMask
        guard changedMask != 0 else {
            return
        }

        for (paddle, bit) in paddleBits {
            guard changedMask & bit != 0 else {
                continue
            }

            let isPressed = (newMask & bit) != 0
            let state = isPressed ? "pressed" : "released"
            if onPaddleChange != nil {
                log("\(paddle.consoleName) \(state)")
            }
            onPaddleChange?(paddle, isPressed)
        }

        aggregatePaddleMask = newMask
    }

    private func detectPaddleDevices(logDevices: Bool) -> DetectedPaddleDevices {
        var detectedDevices: [DetectedPaddleDevice] = []
        var unsupportedDevices: [DetectedPaddleDevice] = []
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty {
            let sortedDevices = devices
                .map { device in (device: device, info: controllerInfo(for: device)) }
                .sorted(by: deviceDiscoverySort(_:_:))

            for (device, info) in sortedDevices {
                if logDevices {
                    log("Raw HID device found: \(deviceDescription(device))")
                }

                let detectedDevice = DetectedPaddleDevice(
                    runtimeID: deviceIdentifier(device),
                    info: info,
                    discoveryOrder: discoveryOrder(for: info.identifier)
                )

                if let paddleElementKind = firstPaddleInputElementKind(in: device) {
                    detectedDevices.append(detectedDevice)
                    if logDevices {
                        log("Raw HID \(paddleElementKind.logDescription)")
                    }
                } else {
                    unsupportedDevices.append(detectedDevice)
                    if logDevices {
                        log("Raw HID paddle mask element not found on this device.")
                    }
                }
            }
        } else if logDevices {
            log("No Microsoft gamepad HID devices found yet.")
        }

        return DetectedPaddleDevices(devices: detectedDevices, unsupportedDevices: unsupportedDevices)
    }

    private func deviceDiscoverySort(
        _ lhs: (device: IOHIDDevice, info: HIDPaddleControllerInfo),
        _ rhs: (device: IOHIDDevice, info: HIDPaddleControllerInfo)
    ) -> Bool {
        let lhsKnownOrder = controllerDiscoveryOrderByIdentifier[lhs.info.identifier]
        let rhsKnownOrder = controllerDiscoveryOrderByIdentifier[rhs.info.identifier]
        if lhsKnownOrder != rhsKnownOrder {
            return (lhsKnownOrder ?? Int.max) < (rhsKnownOrder ?? Int.max)
        }

        if lhs.info.productName != rhs.info.productName {
            return lhs.info.productName.localizedCaseInsensitiveCompare(rhs.info.productName) == .orderedAscending
        }

        return lhs.info.identifier < rhs.info.identifier
    }

    private func discoveryOrder(for controllerIdentifier: String) -> Int {
        if let existingOrder = controllerDiscoveryOrderByIdentifier[controllerIdentifier] {
            return existingOrder
        }

        let order = nextControllerDiscoveryOrder
        controllerDiscoveryOrderByIdentifier[controllerIdentifier] = order
        nextControllerDiscoveryOrder += 1
        return order
    }

    private func updateDeviceStatus(_ status: HIDPaddleDeviceStatus, notifyWhenUnchanged: Bool) {
        let didChange = status != lastDeviceStatus
        lastDeviceStatus = status

        if didChange || notifyWhenUnchanged {
            onDeviceStatusChange?(status)
        }
    }


    private func firstPaddleInputElementKind(in device: IOHIDDevice) -> PaddleInputElementKind? {
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else {
            return nil
        }

        for element in elements {
            if let kind = paddleInputElementKind(for: element) {
                return kind
            }
        }

        return nil
    }

    private func paddleInputElementKind(for element: IOHIDElement) -> PaddleInputElementKind? {
        if isBluetoothPaddleMaskElement(element) {
            return .bluetoothPaddleMask
        }

        return nil
    }

    private func isBluetoothPaddleMaskElement(_ element: IOHIDElement) -> Bool {
        IOHIDElementGetReportID(element) == Constants.bluetoothPaddleMaskReportID &&
            IOHIDElementGetUsagePage(element) == Constants.bluetoothPaddleMaskUsagePage &&
            IOHIDElementGetUsage(element) == Constants.bluetoothPaddleMaskUsage
    }


    private func paddleMask(from rawValue: Int, elementKind: PaddleInputElementKind) -> Int {
        switch elementKind {
        case .bluetoothPaddleMask:
            return rawValue & 0x0F
        }
    }

    private var paddleBits: [(Paddle, Int)] {
        [
            (.one, 0x01),
            (.two, 0x02),
            (.three, 0x04),
            (.four, 0x08)
        ]
    }

    private func controllerInfo(for device: IOHIDDevice) -> HIDPaddleControllerInfo {
        HIDPaddleControllerInfo(
            identifier: stableControllerIdentifier(for: device),
            productName: deviceProductName(device),
            transport: optionalHIDProperty(device, kIOHIDTransportKey as CFString),
            vendorID: normalizedHIDNumber(device, kIOHIDVendorIDKey as CFString),
            productID: normalizedHIDNumber(device, kIOHIDProductIDKey as CFString)
        )
    }

    private func stableControllerIdentifier(for device: IOHIDDevice) -> String {
        let vendorID = normalizedHIDNumber(device, kIOHIDVendorIDKey as CFString) ?? "vendor-missing"
        let productID = normalizedHIDNumber(device, kIOHIDProductIDKey as CFString) ?? "product-missing"
        let transport = optionalHIDProperty(device, kIOHIDTransportKey as CFString) ?? "transport-missing"

        if let serialNumber = optionalHIDProperty(device, kIOHIDSerialNumberKey as CFString) {
            return "hid:vendor=\(vendorID):product=\(productID):serial=\(serialNumber)"
        }

        if let locationID = normalizedHIDNumber(device, kIOHIDLocationIDKey as CFString) {
            return "hid:vendor=\(vendorID):product=\(productID):transport=\(transport):location=\(locationID)"
        }

        return "hid:vendor=\(vendorID):product=\(productID):transport=\(transport):runtime=\(deviceIdentifier(device))"
    }

    private func deviceProductName(_ device: IOHIDDevice) -> String {
        optionalHIDProperty(device, kIOHIDProductKey as CFString) ?? "Unknown Controller"
    }

    private func deviceIdentifier(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func deviceDescription(_ device: IOHIDDevice) -> String {
        let product = deviceProductName(device)
        let transport = optionalHIDProperty(device, kIOHIDTransportKey as CFString) ?? "(missing)"
        let vendorID = normalizedHIDNumber(device, kIOHIDVendorIDKey as CFString) ?? "(missing)"
        let productID = normalizedHIDNumber(device, kIOHIDProductIDKey as CFString) ?? "(missing)"
        let serialNumber = optionalHIDProperty(device, kIOHIDSerialNumberKey as CFString) ?? "(missing)"
        let locationID = normalizedHIDNumber(device, kIOHIDLocationIDKey as CFString) ?? "(missing)"
        return "\(product) transport=\(transport) vendorID=\(vendorID) productID=\(productID) serial=\(serialNumber) locationID=\(locationID)"
    }

    private func optionalHIDProperty(_ device: IOHIDDevice, _ key: CFString) -> String? {
        guard let property = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }

        let value = String(describing: property).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "(missing)" else {
            return nil
        }
        return value
    }

    private func normalizedHIDNumber(_ device: IOHIDDevice, _ key: CFString) -> String? {
        guard let property = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }

        if CFGetTypeID(property) == CFNumberGetTypeID() {
            var number: Int64 = 0
            guard CFNumberGetValue((property as! CFNumber), .sInt64Type, &number) else {
                return nil
            }
            return String(number, radix: 16, uppercase: false)
        }

        return optionalHIDProperty(device, key)
    }

    private static func defaultLog(_ message: String) {
        print(message)
        fflush(stdout)
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else {
            return
        }

        let monitor = Unmanaged<HIDPaddleMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handle(value: value)
    }
}
