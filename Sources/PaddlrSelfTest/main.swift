import CoreGraphics
import Darwin
import PaddlrCore
import Foundation

func fail(_ message: String) -> Never {
    fputs("Self-test failed: \(message)\n", stderr)
    exit(EXIT_FAILURE)
}

let expectedConsoleNames = ["P1", "P2", "P3", "P4"]
let actualConsoleNames = Paddle.allCases.map(\.consoleName)

guard actualConsoleNames == expectedConsoleNames else {
    fail("expected console names \(expectedConsoleNames), got \(actualConsoleNames)")
}

let expectedDisplayNames = ["Paddle 1", "Paddle 2", "Paddle 3", "Paddle 4"]
let actualDisplayNames = Paddle.allCases.map(\.displayName)

guard actualDisplayNames == expectedDisplayNames else {
    fail("expected display names \(expectedDisplayNames), got \(actualDisplayNames)")
}

for paddle in Paddle.allCases where paddle.gameControllerInputName.isEmpty {
    fail("GameController input name is empty for \(paddle.consoleName)")
}

let defaultSyntheticKeys: [SyntheticKey] = [.f13, .f14, .f15, .f16]
let defaultSyntheticKeyNames = defaultSyntheticKeys.map(\.displayName)

guard defaultSyntheticKeyNames == ["F13", "F14", "F15", "F16"] else {
    fail("expected default synthetic keys F13-F16, got \(defaultSyntheticKeyNames)")
}

let syntheticKeyRawValues = SyntheticKey.allCases.map(\.rawValue)
let uniqueSyntheticKeyRawValues = Set(syntheticKeyRawValues)

guard uniqueSyntheticKeyRawValues.count == syntheticKeyRawValues.count else {
    fail("synthetic key raw values must be unique")
}

for defaultKey in defaultSyntheticKeys {
    guard SyntheticKey(rawValue: defaultKey.rawValue) == defaultKey else {
        fail("expected persisted raw value \(defaultKey.rawValue) to round-trip")
    }
}

let disconnectedStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
guard disconnectedStatus.connectedDeviceCount == 0 else {
    fail("expected disconnected HID status count to be 0, got \(disconnectedStatus.connectedDeviceCount)")
}

let connectedStatus = HIDPaddleDeviceStatus(isConnected: true, deviceName: "Xbox Wireless Controller")
guard connectedStatus.connectedDeviceCount == 1 else {
    fail("expected connected HID status default count to be 1, got \(connectedStatus.connectedDeviceCount)")
}

let controllerInfo = HIDPaddleControllerInfo(
    identifier: "hid:vendor=45e:product=b22:serial=example",
    productName: "Xbox Wireless Controller",
    transport: "Bluetooth Low Energy",
    vendorID: "45e",
    productID: "b22"
)
let unsupportedControllerStatus = HIDPaddleDeviceStatus(
    isConnected: false,
    deviceName: nil,
    unsupportedControllers: [controllerInfo]
)
guard unsupportedControllerStatus.unsupportedControllerCount == 1 else {
    fail("expected unsupported HID status count to be 1, got \(unsupportedControllerStatus.unsupportedControllerCount)")
}
guard unsupportedControllerStatus.unsupportedControllerName == controllerInfo.productName else {
    fail("expected unsupported HID controller name to be preserved")
}

let multiControllerStatus = HIDPaddleDeviceStatus(
    isConnected: true,
    deviceName: "Xbox Wireless Controller",
    connectedDeviceCount: 2,
    controllers: [controllerInfo]
)
guard multiControllerStatus.connectedDeviceCount == 2 else {
    fail("expected multi-controller HID status count to be 2, got \(multiControllerStatus.connectedDeviceCount)")
}
guard multiControllerStatus.controllers.first?.identifier == controllerInfo.identifier else {
    fail("expected HID controller identifiers to be preserved")
}

guard controllerInfo.isKnownXboxEliteSeries2 else {
    fail("expected product ID 0x0b22 to be recognized as known Xbox Elite Series 2")
}

let regularControllerInfo = HIDPaddleControllerInfo(
    identifier: "hid:vendor=45e:product=b13:serial=regular",
    productName: "Xbox Wireless Controller",
    vendorID: "45e",
    productID: "b13"
)
guard !regularControllerInfo.isKnownXboxEliteSeries2 else {
    fail("expected regular Xbox Series controller PID 0x0b13 not to be marked Elite")
}

let knownElitePIDs = ["b00", "0x0b05", "0B22"]
for productID in knownElitePIDs {
    let eliteInfo = HIDPaddleControllerInfo(
        identifier: "hid:vendor=45e:product=\(productID)",
        productName: "Xbox Wireless Controller",
        vendorID: "0x045e",
        productID: productID
    )
    guard eliteInfo.isKnownXboxEliteSeries2 else {
        fail("expected product ID \(productID) to be recognized as known Xbox Elite Series 2")
    }
}

let expectedExpandedKeys: [SyntheticKey] = [
    .escape,
    .tab,
    .space,
    .returnKey,
    .delete,
    .upArrow,
    .downArrow,
    .leftArrow,
    .rightArrow,
    .a,
    .z,
    .zero,
    .nine,
    .f1,
    .f12,
    .f20,
    .shift,
    .control,
    .option,
    .command
]

for key in expectedExpandedKeys {
    guard SyntheticKey.allCases.contains(key) else {
        fail("expanded synthetic key catalog is missing \(key.displayName)")
    }

    _ = key.keyCode
    _ = key.keyboardMapping
}

let keyboardMapping = KeyboardMapping(
    keyCode: SyntheticKey.a.keyCode,
    modifierFlagsRawValue: CGEventFlags.maskCommand.rawValue,
    keyDisplayName: "A"
)

guard keyboardMapping.displayName == "Command+A" else {
    fail("expected Command+A display name, got \(keyboardMapping.displayName)")
}

let defaultProfile = MappingProfile.defaultProfile

guard defaultProfile.name == "Default" else {
    fail("expected default profile name to be Default, got \(defaultProfile.name)")
}

guard defaultProfile.action(for: .one).displayName == "F13" else {
    fail("expected default P1 action to be F13, got \(defaultProfile.action(for: .one).displayName)")
}

let migratedProfile = MappingProfile.defaultProfile(legacySyntheticMappings: [.one: .space, .two: .tab])

guard migratedProfile.action(for: .one).displayName == "Space" else {
    fail("expected migrated P1 action to be Space, got \(migratedProfile.action(for: .one).displayName)")
}

guard migratedProfile.action(for: .three).displayName == "F15" else {
    fail("expected missing legacy P3 action to fall back to F15, got \(migratedProfile.action(for: .three).displayName)")
}

let encoder = JSONEncoder()
let decoder = JSONDecoder()

do {
    let profileData = try encoder.encode(migratedProfile)
    let decodedProfile = try decoder.decode(MappingProfile.self, from: profileData)
    guard decodedProfile == migratedProfile else {
        fail("mapping profile did not round-trip through Codable")
    }

    let action = PaddleAction.keyboard(keyboardMapping)
    let actionData = try encoder.encode(action)
    let decodedAction = try decoder.decode(PaddleAction.self, from: actionData)
    guard decodedAction == action else {
        fail("paddle action did not round-trip through Codable")
    }

    let rule = AppProfileRule(
        bundleIdentifier: "com.example.Game",
        appName: "Example Game",
        action: .useProfile(migratedProfile.id)
    )
    let ruleData = try encoder.encode(rule)
    let decodedRule = try decoder.decode(AppProfileRule.self, from: ruleData)
    guard decodedRule == rule else {
        fail("app profile rule did not round-trip through Codable")
    }

    let controllerRule = AppProfileRule(
        bundleIdentifier: "com.example.Game",
        appName: "Example Game",
        controllerIdentifier: controllerInfo.identifier,
        action: .useProfile(migratedProfile.id)
    )
    let controllerRuleData = try encoder.encode(controllerRule)
    let decodedControllerRule = try decoder.decode(AppProfileRule.self, from: controllerRuleData)
    guard decodedControllerRule == controllerRule else {
        fail("controller-specific app profile rule did not round-trip through Codable")
    }
} catch {
    fail("Codable validation failed: \(error.localizedDescription)")
}

print("Paddlr self-test passed.")
print("Paddles: \(actualConsoleNames.joined(separator: ", "))")
print("Default synthetic keys: \(defaultSyntheticKeyNames.joined(separator: ", "))")
print("Synthetic key catalog size: \(SyntheticKey.allCases.count)")
print("Profile/action/app-rule Codable round trips passed.")
