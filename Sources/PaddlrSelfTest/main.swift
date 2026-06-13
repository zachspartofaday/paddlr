import CoreGraphics
import Darwin
import PaddlrCore
import Foundation

func fail(_ message: String) -> Never {
    fputs("Self-test failed: \(message)\n", stderr)
    exit(EXIT_FAILURE)
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fail("\(message): expected \(expected), got \(actual)")
    }
}

func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fail(message)
    }
}

func makeIsolatedDefaults(name: String) -> UserDefaults {
    let suiteName = "com.paddlr.selftest.\(name).\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fail("could not create isolated defaults suite \(suiteName)")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
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

let defaultProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
let appProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
let controllerProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
let missingProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000009999")!
let defaultResolverProfile = MappingProfile(id: defaultProfileID, name: "Default", actions: MappingProfile.defaultActions)
let appResolverProfile = MappingProfile(id: appProfileID, name: "App", actions: [.one: .keyboard(.space)])
let controllerResolverProfile = MappingProfile(id: controllerProfileID, name: "Controller", actions: [.one: .keyboard(.tab)])
let resolverProfiles = [defaultResolverProfile, appResolverProfile, controllerResolverProfile]
let controllerIdentifier = "controller-a"
let resolverRules = [
    AppProfileRule(
        bundleIdentifier: "com.example.Game",
        appName: "Example Game",
        action: .useProfile(appProfileID)
    ),
    AppProfileRule(
        bundleIdentifier: "com.example.Game",
        appName: "Example Game",
        controllerIdentifier: controllerIdentifier,
        action: .useProfile(controllerProfileID)
    ),
    AppProfileRule(
        bundleIdentifier: "com.example.Disabled",
        appName: "Disabled",
        action: .disableOutput
    ),
    AppProfileRule(
        bundleIdentifier: "com.example.Missing",
        appName: "Missing",
        action: .useProfile(missingProfileID)
    )
]
let resolverConfigurations = [
    ControllerConfiguration(
        identifier: controllerIdentifier,
        productName: "Xbox Wireless Controller",
        profileID: controllerProfileID
    )
]
let resolver = ProfileResolver(
    profiles: resolverProfiles,
    appRules: resolverRules,
    controllerConfigurations: resolverConfigurations,
    defaultProfileID: defaultProfileID,
    selectedProfileID: defaultProfileID,
    outputEnabled: true,
    defaultApplicationOutputEnabled: true
)

struct ResolverCase {
    var name: String
    var bundleIdentifier: String?
    var controllerIdentifier: String?
    var expectedProfileID: UUID
    var expectedOutputEnabled: Bool
}

let resolverCases = [
    ResolverCase(
        name: "default app",
        bundleIdentifier: nil,
        controllerIdentifier: nil,
        expectedProfileID: defaultProfileID,
        expectedOutputEnabled: true
    ),
    ResolverCase(
        name: "app rule",
        bundleIdentifier: "com.example.Game",
        controllerIdentifier: nil,
        expectedProfileID: appProfileID,
        expectedOutputEnabled: true
    ),
    ResolverCase(
        name: "controller-specific app rule",
        bundleIdentifier: "com.example.Game",
        controllerIdentifier: controllerIdentifier,
        expectedProfileID: controllerProfileID,
        expectedOutputEnabled: true
    ),
    ResolverCase(
        name: "controller default",
        bundleIdentifier: nil,
        controllerIdentifier: controllerIdentifier,
        expectedProfileID: controllerProfileID,
        expectedOutputEnabled: true
    ),
    ResolverCase(
        name: "disabled output",
        bundleIdentifier: "com.example.Disabled",
        controllerIdentifier: nil,
        expectedProfileID: defaultProfileID,
        expectedOutputEnabled: false
    ),
    ResolverCase(
        name: "missing profile",
        bundleIdentifier: "com.example.Missing",
        controllerIdentifier: nil,
        expectedProfileID: defaultProfileID,
        expectedOutputEnabled: true
    )
]

for resolverCase in resolverCases {
    expectEqual(
        resolver.profileIDForApplication(
            bundleIdentifier: resolverCase.bundleIdentifier,
            controllerIdentifier: resolverCase.controllerIdentifier
        ),
        resolverCase.expectedProfileID,
        "resolver \(resolverCase.name) profile"
    )
    expectEqual(
        resolver.effectiveOutputEnabled(
            bundleIdentifier: resolverCase.bundleIdentifier,
            controllerIdentifier: resolverCase.controllerIdentifier
        ),
        resolverCase.expectedOutputEnabled,
        "resolver \(resolverCase.name) output"
    )
}

let globallyDisabledResolver = ProfileResolver(
    profiles: resolverProfiles,
    appRules: resolverRules,
    controllerConfigurations: resolverConfigurations,
    defaultProfileID: defaultProfileID,
    selectedProfileID: defaultProfileID,
    outputEnabled: false,
    defaultApplicationOutputEnabled: true
)
expectEqual(
    globallyDisabledResolver.effectiveOutputEnabled(bundleIdentifier: "com.example.Game", controllerIdentifier: nil),
    false,
    "resolver global output disabled"
)

let defaultOutputDisabledResolver = ProfileResolver(
    profiles: resolverProfiles,
    appRules: resolverRules,
    controllerConfigurations: resolverConfigurations,
    defaultProfileID: defaultProfileID,
    selectedProfileID: defaultProfileID,
    outputEnabled: true,
    defaultApplicationOutputEnabled: false
)
expectEqual(
    defaultOutputDisabledResolver.effectiveOutputEnabled(bundleIdentifier: nil, controllerIdentifier: nil),
    false,
    "resolver default application output disabled"
)
expectEqual(
    defaultOutputDisabledResolver.effectiveOutputEnabled(bundleIdentifier: "com.example.Game", controllerIdentifier: nil),
    true,
    "resolver app rule overrides default application output disabled"
)

let controllerCoordinator = ControllerSelectionCoordinator()
let firstController = HIDPaddleControllerInfo(identifier: "controller-a", productName: "Xbox Wireless Controller")
let secondController = HIDPaddleControllerInfo(identifier: "controller-b", productName: "Xbox Wireless Controller")
let registration = controllerCoordinator.registerConnectedControllers(
    [firstController, secondController],
    configurations: []
)
expectEqual(registration.newlyAssignedPrimaryIdentifier, firstController.identifier, "first controller becomes primary")
expect(registration.configurations.first(where: { $0.identifier == firstController.identifier })?.isPrimary == true, "registered first controller should be primary")
expect(registration.configurations.first(where: { $0.identifier == secondController.identifier })?.isPrimary == false, "registered second controller should not be primary")

let sortedSelections = controllerCoordinator.visibleSelections(
    configurations: [
        ControllerConfiguration(identifier: "primary", productName: "Primary", isPrimary: true),
        ControllerConfiguration(identifier: "pinned-b", productName: "Pinned B", displayName: "Zulu", isPinned: true),
        ControllerConfiguration(identifier: "pinned-a", productName: "Pinned A", displayName: "Alpha", isPinned: true),
        ControllerConfiguration(identifier: "connected", productName: "Connected")
    ],
    connectedControllers: [HIDPaddleControllerInfo(identifier: "connected", productName: "Connected")]
)
expectEqual(
    sortedSelections.map(\.identifier),
    ["primary", "pinned-a", "pinned-b", "connected"],
    "controller primary/pinned sorting"
)
expect(sortedSelections.contains(where: { $0.identifier == "pinned-a" && !$0.isConnected }), "disconnected pinned controller should remain visible")

let fallbackState = controllerCoordinator.selectionAfterStatusChange(
    selections: [
        ControllerSelection(
            identifier: "pinned",
            displayName: "Pinned",
            productName: "Pinned",
            index: 1,
            isConnected: false,
            isPinned: true,
            isPrimary: true,
            hasCustomDisplayName: true
        ),
        ControllerSelection(
            identifier: "connected",
            displayName: "Connected",
            productName: "Connected",
            index: 2,
            isConnected: true,
            isPinned: false,
            isPrimary: false,
            hasCustomDisplayName: false
        )
    ],
    selectedControllerIdentifier: "pinned",
    selectionWasUserInitiated: false
)
expectEqual(fallbackState.selectedControllerIdentifier, "connected", "non-user-selected disconnected controller falls back to connected")
expectEqual(fallbackState.selectionWasUserInitiated, false, "fallback selection remains non-user initiated")

do {
    let defaults = makeIsolatedDefaults(name: "legacy-fallback")
    let store = PaddlrSettingsStore(defaults: defaults)
    let legacyProfile = MappingProfile(id: appProfileID, name: "Legacy", actions: [.one: .keyboard(.space)])
    let legacyRule = AppProfileRule(
        bundleIdentifier: "com.example.Legacy",
        appName: "Legacy",
        action: .useProfile(appProfileID)
    )
    let legacyControllerConfiguration = ControllerConfiguration(identifier: "legacy-controller", profileID: appProfileID)
    defaults.set(try encoder.encode([legacyProfile]), forKey: PaddlrSettingsStore.legacyProfilesDefaultsKey)
    defaults.set(try encoder.encode([legacyRule]), forKey: PaddlrSettingsStore.legacyAppRulesDefaultsKey)
    defaults.set(
        try encoder.encode([legacyControllerConfiguration]),
        forKey: PaddlrSettingsStore.legacyControllerConfigurationsDefaultsKey
    )
    defaults.set(false, forKey: PaddlrSettingsStore.legacyOutputEnabledDefaultsKey)
    defaults.set(false, forKey: PaddlrSettingsStore.legacyDefaultApplicationOutputEnabledDefaultsKey)

    expectEqual(store.loadProfiles(), [legacyProfile], "settings store legacy profile fallback")
    expectEqual(store.loadAppRules(), [legacyRule], "settings store legacy app rule fallback")
    expectEqual(
        store.loadControllerConfigurations(),
        [legacyControllerConfiguration],
        "settings store legacy controller configuration fallback"
    )
    expectEqual(store.loadOutputEnabled(), false, "settings store legacy output fallback")
    expectEqual(
        store.loadDefaultApplicationOutputEnabled(),
        false,
        "settings store legacy default application output fallback"
    )
}

do {
    let defaults = makeIsolatedDefaults(name: "normalization")
    let store = PaddlrSettingsStore(defaults: defaults)
    let legacyNamedDefault = MappingProfile(
        id: defaultProfileID,
        name: "Untitled Preset",
        actions: MappingProfile.defaultActions
    )
    defaults.set(try encoder.encode([legacyNamedDefault]), forKey: PaddlrSettingsStore.profilesDefaultsKey)
    expectEqual(store.loadProfiles().first?.name, MappingProfile.defaultProfileName, "settings store default-profile normalization")
}

do {
    let defaults = makeIsolatedDefaults(name: "selected-profile-fallback")
    let store = PaddlrSettingsStore(defaults: defaults)
    defaults.set(missingProfileID.uuidString, forKey: PaddlrSettingsStore.selectedProfileIDDefaultsKey)
    expectEqual(
        store.loadSelectedProfileID(availableProfiles: resolverProfiles),
        defaultProfileID,
        "settings store selected profile fallback"
    )
}

do {
    let defaults = makeIsolatedDefaults(name: "current-key-writes")
    let store = PaddlrSettingsStore(defaults: defaults)
    let pinnedApplication = PinnedApplication(bundleIdentifier: "com.example.Game", appName: "Example Game")
    try store.writeProfiles(resolverProfiles)
    try store.writeAppRules(resolverRules)
    try store.writePinnedApplications([pinnedApplication])
    try store.writeControllerConfigurations(resolverConfigurations)
    store.writeSelectedProfileID(appProfileID)
    store.writeOutputEnabled(false)
    store.writeDefaultApplicationOutputEnabled(false)

    expect(defaults.data(forKey: PaddlrSettingsStore.profilesDefaultsKey) != nil, "settings store should write current profiles key")
    expect(defaults.data(forKey: PaddlrSettingsStore.appRulesDefaultsKey) != nil, "settings store should write current app rules key")
    expect(defaults.data(forKey: PaddlrSettingsStore.pinnedApplicationsDefaultsKey) != nil, "settings store should write current pinned apps key")
    expect(defaults.data(forKey: PaddlrSettingsStore.controllerConfigurationsDefaultsKey) != nil, "settings store should write current controller settings key")
    expectEqual(defaults.string(forKey: PaddlrSettingsStore.selectedProfileIDDefaultsKey), appProfileID.uuidString, "settings store should write selected profile current key")
    expectEqual(store.loadOutputEnabled(), false, "settings store current output key write")
    expectEqual(
        store.loadDefaultApplicationOutputEnabled(),
        false,
        "settings store current default application output key write"
    )
    expectEqual(store.loadPinnedApplications(), [pinnedApplication], "settings store pinned app write round trip")
}

let f13Mapping = SyntheticKey.f13.keyboardMapping
let f14Mapping = SyntheticKey.f14.keyboardMapping
let sourceAOne = KeyboardOutputSource(controllerIdentifier: "controller-a", paddle: .one)
let sourceATwo = KeyboardOutputSource(controllerIdentifier: "controller-a", paddle: .two)
let sourceBOne = KeyboardOutputSource(controllerIdentifier: "controller-b", paddle: .one)

do {
    var tracker = KeyboardOutputSessionTracker()
    expectEqual(tracker.setKeyboard(f13Mapping, isPressed: true, source: sourceAOne), .keyDown(f13Mapping), "keyboard tracker duplicate first key down")
    expectEqual(tracker.setKeyboard(f13Mapping, isPressed: true, source: sourceATwo), nil, "keyboard tracker duplicate second key down")
    expectEqual(tracker.setKeyboard(f13Mapping, isPressed: false, source: sourceAOne), nil, "keyboard tracker duplicate first key up deferred")
    expectEqual(tracker.setKeyboard(f13Mapping, isPressed: false, source: sourceATwo), .keyUp(f13Mapping), "keyboard tracker duplicate final key up")
}

do {
    var tracker = KeyboardOutputSessionTracker()
    expectEqual(tracker.setKeyboard(f13Mapping, isPressed: false, source: sourceAOne), .keyUp(f13Mapping), "keyboard tracker release without prior press")
}

do {
    var tracker = KeyboardOutputSessionTracker()
    _ = tracker.setKeyboard(f13Mapping, isPressed: true, source: sourceAOne)
    _ = tracker.setKeyboard(f13Mapping, isPressed: true, source: sourceBOne)
    expectEqual(tracker.releaseAll(for: ["controller-a"]), [], "keyboard tracker controller-specific release keeps shared mapping down")
    expectEqual(tracker.releaseAll(for: ["controller-b"]), [.keyUp(f13Mapping)], "keyboard tracker disconnect releases final shared mapping")
}

do {
    var tracker = KeyboardOutputSessionTracker()
    _ = tracker.setKeyboard(f13Mapping, isPressed: true, source: sourceAOne)
    _ = tracker.setKeyboard(f14Mapping, isPressed: true, source: sourceBOne)
    expectEqual(
        tracker.releaseAll(for: ["controller-a"]),
        [.keyUp(f13Mapping)],
        "keyboard tracker controller-specific release"
    )
    expectEqual(tracker.releaseAll(), [.keyUp(f14Mapping)], "keyboard tracker release all after controller release")
}

for reason in ["profile/app/rule change release", "output disable release"] {
    var tracker = KeyboardOutputSessionTracker()
    _ = tracker.setKeyboard(f13Mapping, isPressed: true, source: sourceAOne)
    expectEqual(tracker.releaseAll(), [.keyUp(f13Mapping)], "keyboard tracker \(reason)")
}

print("Paddlr self-test passed.")
print("Paddles: \(actualConsoleNames.joined(separator: ", "))")
print("Default synthetic keys: \(defaultSyntheticKeyNames.joined(separator: ", "))")
print("Synthetic key catalog size: \(SyntheticKey.allCases.count)")
print("Profile/action/app-rule Codable round trips passed.")
print("Resolver, controller selection, settings store, and keyboard session tests passed.")
