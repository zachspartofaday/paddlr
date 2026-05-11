import AppKit
import Combine
import Darwin
import PaddlrCore
import Foundation

struct MenuBarStatusItemState: Equatable, Hashable {
    var isEnabledForCurrentApplication: Bool
    var isControllerConnected: Bool
}

struct MenuBarControllerSelection: Identifiable, Hashable {
    var identifier: String
    var displayName: String
    var productName: String
    var index: Int
    var isConnected: Bool
    var isPinned: Bool
    var isPrimary: Bool
    var hasCustomDisplayName: Bool

    var id: String {
        identifier
    }

    var title: String {
        displayName
    }
}

struct MenuBarPinnedApplication: Codable, Equatable, Identifiable, Hashable {
    var bundleIdentifier: String
    var appName: String

    var id: String {
        bundleIdentifier
    }
}

struct ControllerConfiguration: Codable, Equatable {
    var identifier: String
    var productName: String?
    var displayName: String?
    var profileID: UUID?
    var isPinned: Bool
    var isPrimary: Bool

    init(
        identifier: String,
        productName: String? = nil,
        displayName: String? = nil,
        profileID: UUID? = nil,
        isPinned: Bool = false,
        isPrimary: Bool = false
    ) {
        self.identifier = identifier
        self.productName = productName
        self.displayName = displayName
        self.profileID = profileID
        self.isPinned = isPinned
        self.isPrimary = isPrimary
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case productName
        case displayName
        case profileID
        case isPinned
        case isPrimary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }
}

private struct ControllerPaddleKey: Hashable {
    var controllerIdentifier: String
    var paddle: Paddle
}

/// Observable state and orchestration for the Phase 3/4 menu bar app.
final class MenuBarMapperModel: ObservableObject {
    @Published var outputEnabled: Bool {
        didSet {
            guard outputEnabled != oldValue else {
                return
            }

            defaults.set(outputEnabled, forKey: Self.outputEnabledDefaultsKey)
            recordEventFromAnyThread("[Output] Keyboard output \(outputEnabled ? "enabled" : "disabled").")

            if !outputEnabled {
                releasePostedKeys(reason: "output disabled")
            }
            updateStatusItemState()
        }
    }

    @Published var defaultApplicationOutputEnabled: Bool {
        didSet {
            guard defaultApplicationOutputEnabled != oldValue else {
                return
            }

            defaults.set(defaultApplicationOutputEnabled, forKey: Self.defaultApplicationOutputEnabledDefaultsKey)
            appendEvent("[Output] Default application output \(defaultApplicationOutputEnabled ? "enabled" : "disabled").")

            if !defaultApplicationOutputEnabled, activeAppRule == nil {
                releasePostedKeys(reason: "default application output disabled")
            }
            updateStatusItemState()
        }
    }

    @Published var selectedProfileID: UUID {
        didSet {
            guard selectedProfileID != oldValue else {
                return
            }

            guard !isSyncingSelectedProfileFromController else {
                return
            }

            releasePostedKeys(reason: "profile changed")
            if selectedControllerIdentifier == nil {
                defaultSelectedProfileID = selectedProfileID
                defaults.set(selectedProfileID.uuidString, forKey: Self.selectedProfileIDDefaultsKey)
            }
            appendEvent("[Profile] Selected \(selectedProfileName).")
        }
    }

    @Published private(set) var accessibilityTrusted: Bool
    @Published private(set) var inputMonitoringTrusted: Bool
    @Published private(set) var profiles: [MappingProfile]
    @Published private(set) var appRules: [AppProfileRule]
    @Published private(set) var pinnedApplications: [MenuBarPinnedApplication]
    @Published private(set) var controllerConfigurations: [ControllerConfiguration]
    @Published private(set) var selectedControllerIdentifier: String?
    @Published private(set) var frontmostApplication: FrontmostApplicationInfo?
    @Published private(set) var observedApplications: [FrontmostApplicationInfo] = []
    @Published private(set) var capturingPaddle: Paddle?
    @Published private(set) var paddleDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
    @Published private(set) var monitorStatus = "Controller input monitor not started."
    @Published private(set) var pressedPaddles: Set<Paddle> = []
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var mappingChangeRevision = 0
    @Published private(set) var lastChangedPaddles: Set<Paddle> = []
    @Published private(set) var statusItemState = MenuBarStatusItemState(
        isEnabledForCurrentApplication: false,
        isControllerConnected: false
    )

    private static let outputEnabledDefaultsKey = "com.paddlr.phase3.outputEnabled"
    private static let legacyOutputEnabledDefaultsKey = "com.elitemapper.phase3.outputEnabled"
    private static let defaultApplicationOutputEnabledDefaultsKey = "com.paddlr.phase4.defaultApplicationOutputEnabled"
    private static let legacyDefaultApplicationOutputEnabledDefaultsKey = "com.elitemapper.phase4.defaultApplicationOutputEnabled"
    private static let mappingDefaultsPrefix = "com.paddlr.phase3.mapping."
    private static let legacyMappingDefaultsPrefix = "com.elitemapper.phase3.mapping."
    private static let profilesDefaultsKey = "com.paddlr.phase4.profiles.v1"
    private static let legacyProfilesDefaultsKey = "com.elitemapper.phase4.profiles.v1"
    private static let selectedProfileIDDefaultsKey = "com.paddlr.phase4.selectedProfileID"
    private static let legacySelectedProfileIDDefaultsKey = "com.elitemapper.phase4.selectedProfileID"
    private static let appRulesDefaultsKey = "com.paddlr.phase4.appRules.v1"
    private static let legacyAppRulesDefaultsKey = "com.elitemapper.phase4.appRules.v1"
    private static let pinnedApplicationsDefaultsKey = "com.paddlr.phase4.pinnedApplications.v1"
    private static let controllerConfigurationsDefaultsKey = "com.paddlr.phase5.controllerConfigurations.v1"
    private static let legacyControllerConfigurationsDefaultsKey = "com.elitemapper.phase5.controllerConfigurations.v1"
    private static let maxRecentEvents = 40
    private static let maxObservedApplications = 3
    private static let deviceStatusPollInterval: TimeInterval = 3
    private static let debugConsoleLoggingEnabled = MenuBarMapperModel.isEnvironmentFlagEnabled(
        "PADDLR_DEBUG_LOG",
        legacyKey: "ELITEMAPPER_DEBUG_LOG"
    )

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static let eventTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let defaults: UserDefaults
    private var monitor: HIDPaddleMonitor?
    private var frontmostAppMonitor: FrontmostAppMonitor?
    private var keyCaptureMonitor: Any?
    private var deviceStatusPollTimer: Timer?
    private var recentEventBuffer: [String] = []
    private var isRecentEventPublishingEnabled = false
    private var defaultSelectedProfileID: UUID
    private var isSyncingSelectedProfileFromController = false
    private var selectedControllerSelectionWasUserInitiated = false
    private var livePressedPaddlesByController: [String: Set<Paddle>] = [:]
    private var postedKeyboardByControllerPaddle: [ControllerPaddleKey: KeyboardMapping] = [:]

    private lazy var synthesizer = KeyboardOutputSynthesizer { [weak self] message in
        self?.recordEventFromAnyThread("[Keyboard] \(message)")
    }

    var selectedProfile: MappingProfile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles.first ?? .defaultProfile
    }

    var selectedProfileName: String {
        selectedProfile.name
    }

    var canDeleteSelectedProfile: Bool {
        guard let firstProfileID = profiles.first?.id else {
            return false
        }

        return profiles.count > 1 && selectedProfileID != firstProfileID
    }

    var activeAppRule: AppProfileRule? {
        guard let ruleKey = frontmostApplication?.ruleKey else {
            return nil
        }

        return appRule(bundleIdentifier: ruleKey, controllerIdentifier: selectedControllerIdentifier)
    }

    var effectiveProfile: MappingProfile {
        let profileID = profileIDForApplication(
            bundleIdentifier: frontmostApplication?.ruleKey,
            controllerIdentifier: selectedControllerIdentifier
        )
        return profiles.first(where: { $0.id == profileID }) ?? selectedProfile
    }

    var effectiveProfileName: String {
        effectiveProfile.name
    }

    var effectiveOutputEnabled: Bool {
        effectiveOutputEnabled(forControllerIdentifier: selectedControllerIdentifier)
    }

    var currentAppRuleDescription: String {
        guard let activeAppRule else {
            return "No rule"
        }

        return activeAppRule.action.displayName(profileNameForID: profileName(for:))
    }

    var connectedControllerSelections: [MenuBarControllerSelection] {
        let connectedControllersByIdentifier = Dictionary(
            uniqueKeysWithValues: paddleDeviceStatus.controllers.map { ($0.identifier, $0) }
        )
        let visibleConfigurations = controllerConfigurations.filter { configuration in
            configuration.isPrimary ||
                configuration.isPinned ||
                connectedControllersByIdentifier[configuration.identifier] != nil
        }

        return visibleConfigurations
            .sorted(by: controllerConfigurationSort(_:_:))
            .enumerated()
            .map { index, configuration in
                let connectedController = connectedControllersByIdentifier[configuration.identifier]
                let productName = connectedController?.productName ?? configuration.productName ?? "Xbox Wireless Controller"
                let displayName = controllerDisplayName(for: configuration.identifier, fallback: productName)
                return MenuBarControllerSelection(
                    identifier: configuration.identifier,
                    displayName: displayName,
                    productName: productName,
                    index: index + 1,
                    isConnected: connectedController != nil,
                    isPinned: configuration.isPinned,
                    isPrimary: configuration.isPrimary,
                    hasCustomDisplayName: configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
                )
            }
    }

    var selectedControllerSelection: MenuBarControllerSelection? {
        guard let selectedControllerIdentifier else {
            return nil
        }

        return connectedControllerSelections.first(where: { $0.identifier == selectedControllerIdentifier })
    }

    var selectedControllerCanPin: Bool {
        guard let selectedControllerSelection else {
            return false
        }

        return !selectedControllerSelection.isPrimary
    }

    var selectedControllerIsPinned: Bool {
        selectedControllerSelection?.isPinned == true
    }

    var selectedControllerHasCustomDisplayName: Bool {
        selectedControllerSelection?.hasCustomDisplayName == true
    }

    private var selectedControllerPressedPaddles: Set<Paddle> {
        guard let identifier = selectedControllerIdentifier else {
            return Set(livePressedPaddlesByController.values.flatMap { $0 })
        }

        return livePressedPaddlesByController[identifier] ?? []
    }

    private var selectedControllerProfile: MappingProfile {
        guard let identifier = selectedControllerIdentifier else {
            return selectedProfile
        }

        return profileForController(identifier: identifier)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedProfiles = Self.loadProfiles(from: defaults)
        let resolvedProfiles = loadedProfiles.isEmpty ? [MappingProfile.defaultProfile] : loadedProfiles
        self.profiles = resolvedProfiles
        self.appRules = Self.loadAppRules(from: defaults)
        self.pinnedApplications = Self.loadPinnedApplications(from: defaults)
        let loadedControllerConfigurations = Self.loadControllerConfigurations(from: defaults)
        self.controllerConfigurations = loadedControllerConfigurations
        let restoredControllerIdentifier = Self.defaultSelectedControllerIdentifier(from: loadedControllerConfigurations)
        self.selectedControllerIdentifier = restoredControllerIdentifier

        let savedSelectedProfileID = Self.stringDefaults(
            from: defaults,
            key: Self.selectedProfileIDDefaultsKey,
            legacyKey: Self.legacySelectedProfileIDDefaultsKey
        ).compactMap(UUID.init(uuidString:)).first
        let fallbackSelectedProfileID = resolvedProfiles.first?.id ?? MappingProfile.defaultProfile.id
        let initialSelectedProfileID = savedSelectedProfileID.flatMap { savedID in
            resolvedProfiles.contains(where: { $0.id == savedID }) ? savedID : nil
        } ?? fallbackSelectedProfileID
        self.selectedProfileID = initialSelectedProfileID
        self.defaultSelectedProfileID = initialSelectedProfileID

        self.outputEnabled = Self.boolDefault(
            from: defaults,
            key: Self.outputEnabledDefaultsKey,
            legacyKey: Self.legacyOutputEnabledDefaultsKey
        ) ?? true
        self.defaultApplicationOutputEnabled = Self.boolDefault(
            from: defaults,
            key: Self.defaultApplicationOutputEnabledDefaultsKey,
            legacyKey: Self.legacyDefaultApplicationOutputEnabledDefaultsKey
        ) ?? true
        self.accessibilityTrusted = KeyboardOutputSynthesizer.isAccessibilityTrusted(prompt: false)
        self.inputMonitoringTrusted = HIDPaddleMonitor.isInputMonitoringTrusted(prompt: false)

        defaults.set(outputEnabled, forKey: Self.outputEnabledDefaultsKey)
        defaults.set(defaultApplicationOutputEnabled, forKey: Self.defaultApplicationOutputEnabledDefaultsKey)
        persistProfiles()
        persistAppRules()
        persistPinnedApplications()
        persistControllerConfigurations()
        defaults.set(defaultSelectedProfileID.uuidString, forKey: Self.selectedProfileIDDefaultsKey)

        appendEvent("[App] Paddlr menu bar UI started.")
        appendEvent("[Profile] Selected \(selectedProfileName).")
        appendEvent("[Output] Keyboard output \(outputEnabled ? "enabled" : "disabled").")
        appendEvent("[Output] Default application output \(defaultApplicationOutputEnabled ? "enabled" : "disabled").")
        appendEvent("[Accessibility] Permission is \(accessibilityTrusted ? "trusted" : "not trusted").")
        appendEvent("[InputMonitoring] Permission is \(inputMonitoringTrusted ? "trusted" : "not trusted").")
        updateStatusItemState()
        startFrontmostAppMonitor()
        startMonitor()
        startDeviceStatusPolling()
    }

    deinit {
        cancelKeyCapture()
        stopDeviceStatusPolling()
    }

    func shutdown() {
        cancelKeyCapture()
        stopDeviceStatusPolling()
        releasePostedKeys(reason: "app shutdown")
        frontmostAppMonitor?.stop()
        frontmostAppMonitor = nil
        monitor?.stop()
        monitor = nil
    }

    func refreshPaddleMonitor() {
        releasePostedKeys(reason: "controller monitor refresh")
        clearPressedPaddles()
        paddleDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
        monitorStatus = "Refreshing raw IOHID monitor..."
        appendEvent("[IOHID] Retrying Xbox Elite controller detection.")
        monitor?.stop()
        monitor = nil
        startMonitor()
    }

    func setPopoverVisible(_ isVisible: Bool) {
        guard isRecentEventPublishingEnabled != isVisible else {
            return
        }

        isRecentEventPublishingEnabled = isVisible
        if isVisible {
            recentEvents = recentEventBuffer
            publishPressedPaddlesIfVisible()
        }
    }

    func selectController(identifier: String?) {
        guard selectedControllerIdentifier != identifier else {
            return
        }

        selectedControllerSelectionWasUserInitiated = true
        selectedControllerIdentifier = identifier
        syncSelectedProfileForSelectedController()
        publishPressedPaddlesIfVisible()
    }

    func renameSelectedController(to name: String) {
        guard let controller = selectedControllerSelection else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? controller.productName : trimmedName
        updateControllerConfiguration(identifier: controller.identifier) { configuration in
            configuration.productName = controller.productName
            configuration.displayName = finalName
        }
        appendEvent("[Controller] Renamed \(controller.productName) to \(finalName).")
    }

    func pinSelectedController(displayName: String? = nil) {
        guard let controller = selectedControllerSelection, !controller.isPrimary else {
            return
        }

        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updateControllerConfiguration(identifier: controller.identifier) { configuration in
            configuration.productName = controller.productName
            if let trimmedName {
                configuration.displayName = trimmedName
            }
            configuration.isPinned = true
        }

        appendEvent("[Controller] Pinned \(controllerDisplayName(for: controller.identifier, fallback: controller.productName)).")
    }

    func unpinSelectedController() {
        guard let controller = selectedControllerSelection, !controller.isPrimary else {
            return
        }

        updateControllerConfiguration(identifier: controller.identifier) { configuration in
            configuration.isPinned = false
        }

        appendEvent("[Controller] Unpinned \(controller.displayName).")
        syncSelectedControllerAfterStatusChange()
    }

    func isPressed(_ paddle: Paddle) -> Bool {
        selectedControllerPressedPaddles.contains(paddle)
    }

    func action(for paddle: Paddle) -> PaddleAction {
        selectedControllerProfile.action(for: paddle)
    }

    func selectedProfileAction(for paddle: Paddle) -> PaddleAction {
        selectedProfile.action(for: paddle)
    }

    func setSyntheticKey(_ key: SyntheticKey, for paddle: Paddle) {
        setAction(.keyboard(key), for: paddle)
    }

    func setAction(_ action: PaddleAction, for paddle: Paddle) {
        releasePostedKeys(reason: "mapping changed")
        updateSelectedProfile { profile in
            profile.withAction(action, for: paddle)
        }
        lastChangedPaddles = [paddle]
        mappingChangeRevision += 1
        appendEvent("[Mapping] \(paddle.consoleName) changed to \(action.displayName) in \(selectedProfileName).")
    }

    func resetSelectedProfileToDefaults(markAsPendingChange: Bool = true) {
        releasePostedKeys(reason: "profile reset")
        updateSelectedProfile { profile in
            profile.resetToDefaultActions()
        }
        lastChangedPaddles = markAsPendingChange ? Set(Paddle.allCases) : []
        mappingChangeRevision += 1
        appendEvent("[Profile] Reset \(selectedProfileName) to defaults.")
    }

    func createProfile() {
        let newProfile = MappingProfile(name: nextProfileName(base: "New Profile"), actions: MappingProfile.defaultActions)
        profiles.append(newProfile)
        persistProfiles()
        selectedProfileID = newProfile.id
        appendEvent("[Profile] Created \(newProfile.name).")
    }

    func duplicateSelectedProfile() {
        let source = selectedProfile
        let duplicate = MappingProfile(
            name: nextProfileName(base: "\(source.name) Copy"),
            actions: source.actions
        )
        profiles.append(duplicate)
        persistProfiles()
        selectedProfileID = duplicate.id
        appendEvent("[Profile] Duplicated \(source.name) as \(duplicate.name).")
    }

    func deleteSelectedProfile() {
        guard canDeleteSelectedProfile else {
            appendEvent("[Profile] Cannot delete the default or only profile.")
            return
        }

        let deletedProfile = selectedProfile
        releasePostedKeys(reason: "profile deleted")
        profiles.removeAll(where: { $0.id == deletedProfile.id })
        appRules.removeAll { rule in
            if case .useProfile(let profileID) = rule.action {
                return profileID == deletedProfile.id
            }
            return false
        }
        for index in controllerConfigurations.indices where controllerConfigurations[index].profileID == deletedProfile.id {
            controllerConfigurations[index].profileID = nil
        }
        persistProfiles()
        persistAppRules()
        persistControllerConfigurations()
        updateStatusItemState()
        selectedProfileID = profiles.first?.id ?? MappingProfile.defaultProfile.id
        appendEvent("[Profile] Deleted \(deletedProfile.name).")
    }

    func renameSelectedProfile(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName: String
        if trimmedName.isEmpty {
            finalName = selectedProfileID == profiles.first?.id ? MappingProfile.defaultProfileName : "Untitled Profile"
        } else {
            finalName = trimmedName
        }

        updateSelectedProfile { profile in
            profile.withName(finalName)
        }
    }

    func profileName(for profileID: UUID) -> String? {
        profiles.first(where: { $0.id == profileID })?.name
    }

    func startKeyCapture(for paddle: Paddle) {
        cancelKeyCapture()
        capturingPaddle = paddle
        appendEvent("[Capture] Press a key for \(paddle.consoleName).")

        keyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleCaptureEvent(event) ? nil : event
        }
    }

    func cancelKeyCapture() {
        if let keyCaptureMonitor {
            NSEvent.removeMonitor(keyCaptureMonitor)
            self.keyCaptureMonitor = nil
        }

        if let capturingPaddle {
            appendEvent("[Capture] Cancelled capture for \(capturingPaddle.consoleName).")
        }

        capturingPaddle = nil
    }

    func refreshAccessibilityTrust(prompt: Bool) {
        accessibilityTrusted = KeyboardOutputSynthesizer.isAccessibilityTrusted(prompt: prompt)
        appendEvent("[Accessibility] Permission is \(accessibilityTrusted ? "trusted" : "not trusted").")
    }

    func refreshInputMonitoringTrust(prompt: Bool) {
        inputMonitoringTrusted = HIDPaddleMonitor.isInputMonitoringTrusted(prompt: prompt)
        appendEvent("[InputMonitoring] Permission is \(inputMonitoringTrusted ? "trusted" : "not trusted").")

        if inputMonitoringTrusted {
            startMonitor()
        } else if prompt {
            monitorStatus = "Input Monitoring permission needed."
            appendEvent("[InputMonitoring] Approve Paddlr in System Settings, then click the button again if needed.")
        }
    }

    func assignFrontmostAppToSelectedProfile() {
        guard let app = frontmostApplication, let bundleIdentifier = app.ruleKey else {
            appendEvent("[AppRule] Cannot assign rule because the active app has no bundle identifier.")
            return
        }

        setRule(
            AppProfileRule(
                bundleIdentifier: bundleIdentifier,
                appName: app.displayName,
                controllerIdentifier: selectedControllerIdentifier,
                action: .useProfile(selectedProfileID)
            )
        )
    }

    func disableOutputForFrontmostApp() {
        guard let app = frontmostApplication, let bundleIdentifier = app.ruleKey else {
            appendEvent("[AppRule] Cannot assign rule because the active app has no bundle identifier.")
            return
        }

        setRule(
            AppProfileRule(
                bundleIdentifier: bundleIdentifier,
                appName: app.displayName,
                controllerIdentifier: selectedControllerIdentifier,
                action: .disableOutput
            )
        )
    }

    func clearRuleForFrontmostApp() {
        guard let bundleIdentifier = frontmostApplication?.ruleKey else {
            appendEvent("[AppRule] Cannot clear rule because the active app has no bundle identifier.")
            return
        }

        clearAppRule(
            bundleIdentifier: bundleIdentifier,
            appName: frontmostApplication?.displayName,
            controllerIdentifier: selectedControllerIdentifier
        )
    }

    func useSelectedProfileForDefaultApplication() {
        useProfileForDefaultApplication(profileID: selectedProfileID, controllerIdentifier: selectedControllerIdentifier)
    }

    func useProfileForDefaultApplication(profileID: UUID, controllerIdentifier: String? = nil) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            return
        }

        if let controllerIdentifier {
            let fallbackName = connectedControllerSelections.first(where: { $0.identifier == controllerIdentifier })?.productName ?? controllerIdentifier
            releasePostedKeys(for: [controllerIdentifier], reason: "controller default profile saved")
            updateControllerConfiguration(identifier: controllerIdentifier) { configuration in
                configuration.profileID = profileID
            }
            appendEvent("[AppRule] Default for \(controllerDisplayName(for: controllerIdentifier, fallback: fallbackName)) uses \(profile.name).")
        } else {
            releasePostedKeys(reason: "default application profile saved")
            defaultSelectedProfileID = profileID
            defaults.set(profileID.uuidString, forKey: Self.selectedProfileIDDefaultsKey)
            appendEvent("[AppRule] Default application uses \(profile.name).")
        }
    }

    func assignAppToSelectedProfile(bundleIdentifier: String, appName: String, controllerIdentifier: String? = nil) {
        assignApp(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            controllerIdentifier: controllerIdentifier,
            toProfileID: selectedProfileID
        )
    }

    func assignApp(
        bundleIdentifier: String,
        appName: String,
        controllerIdentifier: String? = nil,
        toProfileID profileID: UUID
    ) {
        guard profiles.contains(where: { $0.id == profileID }) else {
            return
        }

        setRule(
            AppProfileRule(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                controllerIdentifier: controllerIdentifier,
                action: .useProfile(profileID)
            )
        )
    }

    func appRule(bundleIdentifier: String, controllerIdentifier: String?) -> AppProfileRule? {
        if
            let controllerIdentifier,
            let controllerRule = appRules.first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.controllerIdentifier == controllerIdentifier
            })
        {
            return controllerRule
        }

        return appRules.first { $0.bundleIdentifier == bundleIdentifier && $0.controllerIdentifier == nil }
    }

    func profileIDForApplication(bundleIdentifier: String?, controllerIdentifier: String?) -> UUID {
        if
            let bundleIdentifier,
            let rule = appRule(bundleIdentifier: bundleIdentifier, controllerIdentifier: controllerIdentifier),
            case .useProfile(let profileID) = rule.action,
            profiles.contains(where: { $0.id == profileID })
        {
            return profileID
        }

        if
            let controllerIdentifier,
            let profileID = controllerConfiguration(for: controllerIdentifier)?.profileID,
            profiles.contains(where: { $0.id == profileID })
        {
            return profileID
        }

        return validDefaultSelectedProfileID()
    }

    func syncSelectedProfileForApplication(bundleIdentifier: String?, controllerIdentifier: String?) {
        syncSelectedProfile(
            to: profileIDForApplication(bundleIdentifier: bundleIdentifier, controllerIdentifier: controllerIdentifier)
        )
    }

    func disableOutputForApp(bundleIdentifier: String, appName: String, controllerIdentifier: String? = nil) {
        setRule(
            AppProfileRule(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                controllerIdentifier: controllerIdentifier,
                action: .disableOutput
            )
        )
    }

    func clearAppRule(bundleIdentifier: String, appName: String? = nil, controllerIdentifier: String? = nil) {
        releasePostedKeys(reason: "app rule cleared")
        var rules = appRules
        rules.removeAll {
            $0.bundleIdentifier == bundleIdentifier && $0.controllerIdentifier == controllerIdentifier
        }
        appRules = rules
        persistAppRules()
        updateStatusItemState()
        appendEvent("[AppRule] Cleared rule for \(appName ?? bundleIdentifier).")
    }

    func isApplicationPinned(bundleIdentifier: String) -> Bool {
        pinnedApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    func pinApplication(bundleIdentifier: String, appName: String) {
        var applications = pinnedApplications
        applications.removeAll { $0.bundleIdentifier == bundleIdentifier }
        applications.append(MenuBarPinnedApplication(bundleIdentifier: bundleIdentifier, appName: appName))
        applications.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        pinnedApplications = applications
        persistPinnedApplications()
        appendEvent("[App] Pinned \(appName).")
    }

    func unpinApplication(bundleIdentifier: String, appName: String? = nil) {
        var applications = pinnedApplications
        applications.removeAll { $0.bundleIdentifier == bundleIdentifier }
        pinnedApplications = applications
        persistPinnedApplications()
        appendEvent("[App] Unpinned \(appName ?? bundleIdentifier).")
    }

    private func startMonitor() {
        inputMonitoringTrusted = HIDPaddleMonitor.isInputMonitoringTrusted(prompt: false)
        guard inputMonitoringTrusted else {
            monitor?.stop()
            monitor = nil
            clearPressedPaddles()
            paddleDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
            monitorStatus = "Input Monitoring permission needed."
            appendEvent("[IOHID] Waiting for Input Monitoring permission before starting controller detection.")
            updateStatusItemState()
            return
        }

        guard monitor == nil else {
            monitor?.pollDeviceStatus()
            return
        }

        monitorStatus = "Starting raw IOHID monitor..."

        let monitor = HIDPaddleMonitor(
            log: { [weak self] message in
                self?.recordEventFromAnyThread("[IOHID] \(message)")
            },
            onDeviceStatusChange: { [weak self] status in
                self?.handleDeviceStatusChangeFromAnyThread(status)
            },
            onPaddleChange: nil,
            onControllerPaddleChange: { [weak self] controller, paddle, isPressed in
                self?.handlePaddleChangeFromAnyThread(controller: controller, paddle: paddle, isPressed: isPressed)
            }
        )

        self.monitor = monitor
        monitor.start()
    }

    private func startDeviceStatusPolling() {
        stopDeviceStatusPolling()
        let timer = Timer(timeInterval: Self.deviceStatusPollInterval, repeats: true) { [weak self] _ in
            self?.monitor?.pollDeviceStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        deviceStatusPollTimer = timer
    }

    private func stopDeviceStatusPolling() {
        deviceStatusPollTimer?.invalidate()
        deviceStatusPollTimer = nil
    }

    private func startFrontmostAppMonitor() {
        let monitor = FrontmostAppMonitor { [weak self] info in
            self?.handleFrontmostApplicationChange(info)
        }
        frontmostAppMonitor = monitor
        monitor.start()
    }

    private func handleFrontmostApplicationChange(_ info: FrontmostApplicationInfo) {
        guard frontmostApplication != info else {
            return
        }

        releasePostedKeys(reason: "frontmost app changed")
        frontmostApplication = info
        rememberObservedApplication(info)
        syncSelectedProfileForSelectedController()
        updateStatusItemState()
        appendEvent("[App] Active app: \(info.displayName).")

        if let activeAppRule {
            appendEvent("[AppRule] Applied \(activeAppRule.action.displayName(profileNameForID: profileName(for:))).")
        }
    }

    private func rememberObservedApplication(_ info: FrontmostApplicationInfo) {
        guard info.ruleKey != nil else {
            return
        }

        observedApplications.removeAll { $0.ruleKey == info.ruleKey }
        observedApplications.insert(info, at: 0)

        if observedApplications.count > Self.maxObservedApplications {
            observedApplications.removeLast(observedApplications.count - Self.maxObservedApplications)
        }
    }

    private func handleDeviceStatusChangeFromAnyThread(_ status: HIDPaddleDeviceStatus) {
        if Thread.isMainThread {
            applyDeviceStatusChange(status)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyDeviceStatusChange(status)
            }
        }
    }

    private func applyDeviceStatusChange(_ status: HIDPaddleDeviceStatus) {
        let previousStatus = paddleDeviceStatus
        guard status != previousStatus else {
            return
        }

        let disconnectedControllerIDs = Set(previousStatus.controllers.map(\.identifier))
            .subtracting(Set(status.controllers.map(\.identifier)))

        paddleDeviceStatus = status
        registerConnectedControllers(status.controllers)
        if !disconnectedControllerIDs.isEmpty {
            releasePostedKeys(for: disconnectedControllerIDs, reason: "controller disconnected")
            for identifier in disconnectedControllerIDs {
                livePressedPaddlesByController.removeValue(forKey: identifier)
            }
            publishPressedPaddlesIfVisible()
        }
        syncSelectedControllerAfterStatusChange()
        updateStatusItemState()

        if previousStatus.isConnected && !status.isConnected {
            releasePostedKeys(reason: "controller disconnected")
            clearPressedPaddles()
            appendEvent("[IOHID] Xbox Elite controller disconnected.")
        } else if !previousStatus.isConnected && status.isConnected {
            appendEvent("[IOHID] Xbox Elite controller connected: \(deviceStatusDescription(status)).")
        } else if previousStatus.isConnected && status.isConnected {
            appendEvent("[IOHID] Xbox Elite controller status changed: \(deviceStatusDescription(status)).")
        } else if !status.isConnected && previousStatus.unsupportedControllerCount == 0 && status.unsupportedControllerCount > 0 {
            appendEvent("[IOHID] Unsupported controller detected: \(unsupportedDeviceStatusDescription(status)).")
        } else if !status.isConnected && previousStatus.unsupportedControllerCount > 0 && status.unsupportedControllerCount == 0 {
            appendEvent("[IOHID] Unsupported controller disconnected.")
        } else if !status.isConnected && previousStatus.unsupportedControllerCount != status.unsupportedControllerCount {
            appendEvent("[IOHID] Unsupported controller status changed: \(unsupportedDeviceStatusDescription(status)).")
        }
    }

    private func deviceStatusDescription(_ status: HIDPaddleDeviceStatus) -> String {
        let deviceName = status.deviceName ?? "Unknown Device"
        guard status.connectedDeviceCount > 1 else {
            return deviceName
        }

        return "\(status.connectedDeviceCount) controllers detected (primary: \(deviceName))"
    }

    private func unsupportedDeviceStatusDescription(_ status: HIDPaddleDeviceStatus) -> String {
        let knownEliteControllers = status.unsupportedControllers.filter(\.isKnownXboxEliteSeries2)
        if !knownEliteControllers.isEmpty {
            guard knownEliteControllers.count > 1 else {
                let deviceName = knownEliteControllers.first?.productName ?? "Elite 2 Controller"
                return "\(deviceName) is a known Elite 2, but this connection did not expose the supported paddle element"
            }

            return "\(knownEliteControllers.count) known Elite 2 controllers detected without the supported paddle element"
        }

        let deviceName = status.unsupportedControllerName ?? "Unknown Controller"
        guard status.unsupportedControllerCount > 1 else {
            return "\(deviceName) does not expose Elite 2 paddle input"
        }

        return "\(status.unsupportedControllerCount) controllers detected; none expose Elite 2 paddle input"
    }

    private func handlePaddleChangeFromAnyThread(
        controller: HIDPaddleControllerInfo,
        paddle: Paddle,
        isPressed: Bool
    ) {
        if Thread.isMainThread {
            handlePaddleChange(controller: controller, paddle: paddle, isPressed: isPressed)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handlePaddleChange(controller: controller, paddle: paddle, isPressed: isPressed)
            }
        }
    }

    private func handlePaddleChange(controller: HIDPaddleControllerInfo, paddle: Paddle, isPressed: Bool) {
        if isPressed {
            livePressedPaddlesByController[controller.identifier, default: []].insert(paddle)
        } else {
            livePressedPaddlesByController[controller.identifier]?.remove(paddle)
            if livePressedPaddlesByController[controller.identifier]?.isEmpty == true {
                livePressedPaddlesByController.removeValue(forKey: controller.identifier)
            }
        }
        publishPressedPaddlesIfVisible()

        let profile = profileForController(identifier: controller.identifier)
        let action = profile.action(for: paddle)
        let state = isPressed ? "pressed" : "released"
        let controllerName = controllerDisplayName(for: controller)
        appendEvent("[Mapping] \(controllerName) \(paddle.consoleName) \(state) -> \(action.displayName) (\(profile.name)).")

        guard effectiveOutputEnabled(forControllerIdentifier: controller.identifier) else {
            appendEvent("[Output] Disabled; skipped \(action.displayName) \(isPressed ? "down" : "up").")
            return
        }

        switch action {
        case .keyboard(let mapping):
            setKeyboard(mapping, isPressed: isPressed, controllerIdentifier: controller.identifier, paddle: paddle)
        case .disabled:
            appendEvent("[Output] \(controllerName) \(paddle.consoleName) has no output action.")
        }
    }

    private func handleCaptureEvent(_ event: NSEvent) -> Bool {
        guard let paddle = capturingPaddle else {
            return false
        }

        switch event.type {
        case .keyDown:
            let mapping = KeyboardMapping(
                keyCode: CGKeyCode(event.keyCode),
                modifierFlagsRawValue: Self.cgEventFlags(from: event.modifierFlags).rawValue,
                keyDisplayName: KeyboardMapping.defaultDisplayName(for: CGKeyCode(event.keyCode))
            )
            completeCapture(mapping, for: paddle)
            return true
        default:
            return false
        }
    }

    private func completeCapture(_ mapping: KeyboardMapping, for paddle: Paddle) {
        if let keyCaptureMonitor {
            NSEvent.removeMonitor(keyCaptureMonitor)
            self.keyCaptureMonitor = nil
        }

        capturingPaddle = nil
        setAction(.keyboard(mapping), for: paddle)
        appendEvent("[Capture] Captured \(mapping.displayName) for \(paddle.consoleName).")
    }

    private func setKeyboard(
        _ mapping: KeyboardMapping,
        isPressed: Bool,
        controllerIdentifier: String,
        paddle: Paddle
    ) {
        let source = ControllerPaddleKey(controllerIdentifier: controllerIdentifier, paddle: paddle)

        if isPressed {
            guard postedKeyboardByControllerPaddle[source] == nil else {
                return
            }

            let shouldPostKeyDown = !postedKeyboardByControllerPaddle.values.contains(mapping)
            postedKeyboardByControllerPaddle[source] = mapping
            if shouldPostKeyDown {
                synthesizer.setKeyboard(mapping, isPressed: true)
            }
        } else {
            let postedMapping = postedKeyboardByControllerPaddle.removeValue(forKey: source) ?? mapping
            let shouldPostKeyUp = !postedKeyboardByControllerPaddle.values.contains(postedMapping)
            if shouldPostKeyUp {
                synthesizer.setKeyboard(postedMapping, isPressed: false)
            }
        }
    }

    private func releasePostedKeys(for controllerIdentifiers: Set<String>, reason: String) {
        guard !controllerIdentifiers.isEmpty, !postedKeyboardByControllerPaddle.isEmpty else {
            return
        }

        let removedMappings = postedKeyboardByControllerPaddle.compactMap { source, mapping in
            controllerIdentifiers.contains(source.controllerIdentifier) ? mapping : nil
        }
        postedKeyboardByControllerPaddle = postedKeyboardByControllerPaddle.filter { source, _ in
            !controllerIdentifiers.contains(source.controllerIdentifier)
        }

        for mapping in Set(removedMappings).sorted(by: { $0.displayName < $1.displayName }) {
            guard !postedKeyboardByControllerPaddle.values.contains(mapping) else {
                continue
            }
            synthesizer.setKeyboard(mapping, isPressed: false)
            appendEvent("[Output] Released \(mapping.displayName) due to \(reason).")
        }
    }

    private func releasePostedKeys(reason: String) {
        guard !postedKeyboardByControllerPaddle.isEmpty else {
            return
        }

        let postedKeys = postedKeyboardByControllerPaddle
        postedKeyboardByControllerPaddle.removeAll()
        let uniqueMappings = Set(postedKeys.values)

        for mapping in uniqueMappings.sorted(by: { $0.displayName < $1.displayName }) {
            synthesizer.setKeyboard(mapping, isPressed: false)
            appendEvent("[Output] Released \(mapping.displayName) due to \(reason).")
        }
    }

    private func registerConnectedControllers(_ controllers: [HIDPaddleControllerInfo]) {
        guard !controllers.isEmpty else {
            return
        }

        var configurations = controllerConfigurations
        var hasPrimaryController = configurations.contains(where: \.isPrimary)
        var newlyAssignedPrimaryIdentifier: String?

        for controller in controllers {
            let shouldBecomePrimary = !hasPrimaryController
            if let configurationIndex = configurations.firstIndex(where: { $0.identifier == controller.identifier }) {
                configurations[configurationIndex].productName = controller.productName
                if shouldBecomePrimary {
                    configurations[configurationIndex].isPrimary = true
                }
            } else {
                configurations.append(
                    ControllerConfiguration(
                        identifier: controller.identifier,
                        productName: controller.productName,
                        isPrimary: shouldBecomePrimary
                    )
                )
            }

            if shouldBecomePrimary {
                newlyAssignedPrimaryIdentifier = controller.identifier
                hasPrimaryController = true
            }
        }

        if configurations != controllerConfigurations {
            controllerConfigurations = configurations
            persistControllerConfigurations()
        }

        if selectedControllerIdentifier == nil, let newlyAssignedPrimaryIdentifier {
            selectedControllerSelectionWasUserInitiated = false
            selectedControllerIdentifier = newlyAssignedPrimaryIdentifier
            syncSelectedProfileForSelectedController()
        }
    }

    private func syncSelectedControllerAfterStatusChange() {
        let selections = connectedControllerSelections
        if let selectedControllerIdentifier {
            if let selectedController = selections.first(where: { $0.identifier == selectedControllerIdentifier }) {
                if !selectedControllerSelectionWasUserInitiated,
                   !selectedController.isConnected,
                   let firstConnectedController = selections.first(where: \.isConnected) {
                    selectedControllerSelectionWasUserInitiated = false
                    self.selectedControllerIdentifier = firstConnectedController.identifier
                    syncSelectedProfileForSelectedController()
                    publishPressedPaddlesIfVisible()
                    return
                }

                syncSelectedProfileForSelectedController()
                return
            }

            selectedControllerSelectionWasUserInitiated = false
            self.selectedControllerIdentifier = selections.first(where: \.isConnected)?.identifier ?? selections.first?.identifier
            syncSelectedProfileForSelectedController()
            publishPressedPaddlesIfVisible()
            return
        }

        publishPressedPaddlesIfVisible()
    }

    private func syncSelectedProfileForSelectedController() {
        // Profile selection is app/default scoped, with app rules optionally narrowed
        // to the selected controller. Legacy controller-wide assignments are ignored
        // so hidden controller overrides cannot conflict with app-specific choices.
    }

    private func syncSelectedProfile(to profileID: UUID) {
        guard selectedProfileID != profileID else {
            return
        }

        isSyncingSelectedProfileFromController = true
        selectedProfileID = profileID
        isSyncingSelectedProfileFromController = false
    }

    private func profileForController(identifier: String) -> MappingProfile {
        if
            let ruleKey = frontmostApplication?.ruleKey,
            let controllerAppRule = appRule(bundleIdentifier: ruleKey, controllerIdentifier: identifier),
            case .useProfile(let profileID) = controllerAppRule.action,
            let profile = profiles.first(where: { $0.id == profileID })
        {
            return profile
        }

        let fallbackProfileID = fallbackProfileIDForUnassignedController(identifier: identifier)
        return profiles.first(where: { $0.id == fallbackProfileID }) ?? selectedProfile
    }

    private func fallbackProfileIDForUnassignedController(identifier: String?) -> UUID {
        if
            let ruleKey = frontmostApplication?.ruleKey,
            let activeAppRule = appRule(bundleIdentifier: ruleKey, controllerIdentifier: identifier),
            case .useProfile(let profileID) = activeAppRule.action,
            profiles.contains(where: { $0.id == profileID })
        {
            return profileID
        }

        if
            let identifier,
            let profileID = controllerConfiguration(for: identifier)?.profileID,
            profiles.contains(where: { $0.id == profileID })
        {
            return profileID
        }

        return validDefaultSelectedProfileID()
    }

    private func effectiveOutputEnabled(forControllerIdentifier controllerIdentifier: String?) -> Bool {
        guard outputEnabled else {
            return false
        }

        guard
            let ruleKey = frontmostApplication?.ruleKey,
            let activeAppRule = appRule(bundleIdentifier: ruleKey, controllerIdentifier: controllerIdentifier)
        else {
            return defaultApplicationOutputEnabled
        }

        switch activeAppRule.action {
        case .useProfile:
            return true
        case .disableOutput:
            return false
        }
    }

    private func validDefaultSelectedProfileID() -> UUID {
        if profiles.contains(where: { $0.id == defaultSelectedProfileID }) {
            return defaultSelectedProfileID
        }

        return profiles.first?.id ?? selectedProfileID
    }

    private func controllerConfigurationSort(_ lhs: ControllerConfiguration, _ rhs: ControllerConfiguration) -> Bool {
        if lhs.isPrimary != rhs.isPrimary {
            return lhs.isPrimary
        }

        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }

        let lhsName = controllerDisplayName(for: lhs.identifier, fallback: lhs.productName ?? "Xbox Wireless Controller")
        let rhsName = controllerDisplayName(for: rhs.identifier, fallback: rhs.productName ?? "Xbox Wireless Controller")
        if lhsName != rhsName {
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        return lhs.identifier < rhs.identifier
    }

    private func controllerDisplayName(for controller: HIDPaddleControllerInfo) -> String {
        controllerDisplayName(for: controller.identifier, fallback: controller.productName)
    }

    private func controllerDisplayName(for identifier: String, fallback: String) -> String {
        controllerConfiguration(for: identifier)?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }

    private func controllerConfiguration(for identifier: String) -> ControllerConfiguration? {
        controllerConfigurations.first(where: { $0.identifier == identifier })
    }

    private func updateControllerConfiguration(
        identifier: String,
        update: (inout ControllerConfiguration) -> Void
    ) {
        var configurations = controllerConfigurations
        if let index = configurations.firstIndex(where: { $0.identifier == identifier }) {
            update(&configurations[index])
        } else {
            var configuration = ControllerConfiguration(identifier: identifier, displayName: nil, profileID: nil)
            update(&configuration)
            configurations.append(configuration)
        }
        controllerConfigurations = configurations
        persistControllerConfigurations()
    }

    private func setRule(_ rule: AppProfileRule) {
        releasePostedKeys(reason: "app rule changed")
        var rules = appRules
        rules.removeAll {
            $0.bundleIdentifier == rule.bundleIdentifier && $0.controllerIdentifier == rule.controllerIdentifier
        }
        rules.append(rule)
        rules.sort {
            let appOrder = $0.appName.localizedCaseInsensitiveCompare($1.appName)
            if appOrder != .orderedSame {
                return appOrder == .orderedAscending
            }

            return ($0.controllerIdentifier ?? "") < ($1.controllerIdentifier ?? "")
        }
        appRules = rules
        persistAppRules()
        updateStatusItemState()
        appendEvent("[AppRule] \(rule.appName): \(rule.action.displayName(profileNameForID: profileName(for:))).")
    }

    private func updateStatusItemState() {
        let newState = MenuBarStatusItemState(
            isEnabledForCurrentApplication: effectiveOutputEnabled,
            isControllerConnected: paddleDeviceStatus.isConnected
        )
        guard newState != statusItemState else {
            return
        }

        statusItemState = newState
    }

    private func updateSelectedProfile(_ update: (MappingProfile) -> MappingProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return
        }

        profiles[index] = update(profiles[index])
        persistProfiles()
    }

    private func persistProfiles() {
        do {
            let data = try Self.encoder.encode(profiles)
            defaults.set(data, forKey: Self.profilesDefaultsKey)
        } catch {
            appendEvent("[Profile] Failed to persist profiles: \(error.localizedDescription)")
        }
    }

    private func persistAppRules() {
        do {
            let data = try Self.encoder.encode(appRules)
            defaults.set(data, forKey: Self.appRulesDefaultsKey)
        } catch {
            appendEvent("[AppRule] Failed to persist app rules: \(error.localizedDescription)")
        }
    }

    private func persistPinnedApplications() {
        do {
            let data = try Self.encoder.encode(pinnedApplications)
            defaults.set(data, forKey: Self.pinnedApplicationsDefaultsKey)
        } catch {
            appendEvent("[App] Failed to persist pinned apps: \(error.localizedDescription)")
        }
    }

    private func persistControllerConfigurations() {
        do {
            let data = try Self.encoder.encode(controllerConfigurations)
            defaults.set(data, forKey: Self.controllerConfigurationsDefaultsKey)
        } catch {
            appendEvent("[Controller] Failed to persist controller settings: \(error.localizedDescription)")
        }
    }

    private func nextProfileName(base: String) -> String {
        let existingNames = Set(profiles.map(\.name))
        guard existingNames.contains(base) else {
            return base
        }

        var index = 2
        while existingNames.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func recordEventFromAnyThread(_ message: String) {
        if Self.debugConsoleLoggingEnabled {
            print(message)
            fflush(stdout)
        }

        if Thread.isMainThread {
            updateMonitorStatus(from: message)
            appendEvent(message)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateMonitorStatus(from: message)
                self?.appendEvent(message)
            }
        }
    }

    private func appendEvent(_ message: String) {
        let timestamp = Self.eventTimestampFormatter.string(from: Date())
        recentEventBuffer.insert("[\(timestamp)] \(message)", at: 0)

        if recentEventBuffer.count > Self.maxRecentEvents {
            recentEventBuffer.removeLast(recentEventBuffer.count - Self.maxRecentEvents)
        }

        if isRecentEventPublishingEnabled {
            recentEvents = recentEventBuffer
        }
    }

    private func clearPressedPaddles() {
        livePressedPaddlesByController.removeAll()
        publishPressedPaddlesIfVisible()
    }

    private func publishPressedPaddlesIfVisible() {
        guard isRecentEventPublishingEnabled else {
            return
        }

        let visiblePressedPaddles = selectedControllerPressedPaddles
        guard pressedPaddles != visiblePressedPaddles else {
            return
        }

        pressedPaddles = visiblePressedPaddles
    }

    private func updateMonitorStatus(from message: String) {
        if message.contains("Raw IOHID paddle monitor listening") {
            if paddleDeviceStatus.connectedDeviceCount > 1 {
                monitorStatus = "Listening to \(paddleDeviceStatus.connectedDeviceCount) Xbox Elite controllers."
            } else if paddleDeviceStatus.isConnected {
                monitorStatus = "Listening for Xbox Elite paddle input."
            } else if paddleDeviceStatus.unsupportedControllerCount > 0 {
                monitorStatus = "Microsoft controller detected without Elite paddle input."
            } else {
                monitorStatus = "Listening for Xbox Elite paddle input."
            }
        } else if message.contains("Raw HID paddle mask element found") {
            monitorStatus = "Paddle mask detected."
        } else if message.contains("Raw HID paddle mask element not found") {
            monitorStatus = "Microsoft controller detected without Elite paddle input."
        } else if message.contains("No Microsoft gamepad HID devices found") {
            monitorStatus = "Waiting for a Microsoft gamepad."
            paddleDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
        } else if message.contains("unavailable") {
            monitorStatus = "Raw IOHID monitor unavailable."
            paddleDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
        } else if message.contains("Starting raw IOHID paddle monitor") {
            monitorStatus = "Starting raw IOHID monitor..."
        }
    }

    private static func loadProfiles(from defaults: UserDefaults) -> [MappingProfile] {
        for data in dataDefaults(from: defaults, key: profilesDefaultsKey, legacyKey: legacyProfilesDefaultsKey) {
            guard
                let decodedProfiles = try? decoder.decode([MappingProfile].self, from: data),
                !decodedProfiles.isEmpty
            else {
                continue
            }

            return normalizeDefaultProfileName(
                decodedProfiles.map { MappingProfile(id: $0.id, name: $0.name, actions: $0.actions) }
            )
        }

        let legacyMappings = loadLegacySyntheticMappings(from: defaults)
        return [MappingProfile.defaultProfile(legacySyntheticMappings: legacyMappings)]
    }

    private static func normalizeDefaultProfileName(_ profiles: [MappingProfile]) -> [MappingProfile] {
        guard !profiles.isEmpty else {
            return profiles
        }

        var normalizedProfiles = profiles
        let currentName = normalizedProfiles[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyDefaultNames = ["", "Default", "Default Preset", "Untitled Profile", "Untitled Preset"]
        if legacyDefaultNames.contains(currentName) {
            normalizedProfiles[0] = normalizedProfiles[0].withName(MappingProfile.defaultProfileName)
        }

        return normalizedProfiles
    }

    private static func loadLegacySyntheticMappings(from defaults: UserDefaults) -> [Paddle: SyntheticKey] {
        var mappings: [Paddle: SyntheticKey] = [:]

        for paddle in Paddle.allCases {
            guard let key = stringDefaults(
                from: defaults,
                key: mappingDefaultsKey(for: paddle),
                legacyKey: legacyMappingDefaultsKey(for: paddle)
            ).compactMap(SyntheticKey.init(rawValue:)).first else {
                continue
            }

            mappings[paddle] = key
        }

        return mappings
    }

    private static func loadAppRules(from defaults: UserDefaults) -> [AppProfileRule] {
        for data in dataDefaults(from: defaults, key: appRulesDefaultsKey, legacyKey: legacyAppRulesDefaultsKey) {
            if let rules = try? decoder.decode([AppProfileRule].self, from: data) {
                return rules
            }
        }

        return []
    }

    private static func loadPinnedApplications(from defaults: UserDefaults) -> [MenuBarPinnedApplication] {
        guard
            let data = defaults.data(forKey: pinnedApplicationsDefaultsKey),
            let pinnedApplications = try? decoder.decode([MenuBarPinnedApplication].self, from: data)
        else {
            return []
        }

        return pinnedApplications
    }

    private static func loadControllerConfigurations(from defaults: UserDefaults) -> [ControllerConfiguration] {
        for data in dataDefaults(
            from: defaults,
            key: controllerConfigurationsDefaultsKey,
            legacyKey: legacyControllerConfigurationsDefaultsKey
        ) {
            if let configurations = try? decoder.decode([ControllerConfiguration].self, from: data) {
                return configurations
            }
        }

        return []
    }

    private static func defaultSelectedControllerIdentifier(from configurations: [ControllerConfiguration]) -> String? {
        configurations.first(where: \.isPrimary)?.identifier ??
            configurations.first(where: \.isPinned)?.identifier
    }

    private static func mappingDefaultsKey(for paddle: Paddle) -> String {
        "\(mappingDefaultsPrefix)\(paddle.rawValue)"
    }

    private static func legacyMappingDefaultsKey(for paddle: Paddle) -> String {
        "\(legacyMappingDefaultsPrefix)\(paddle.rawValue)"
    }

    private static func dataDefaults(from defaults: UserDefaults, key: String, legacyKey: String) -> [Data] {
        var values: [Data] = []

        if let data = defaults.data(forKey: key) {
            values.append(data)
        }

        if let legacyData = defaults.data(forKey: legacyKey), !values.contains(legacyData) {
            values.append(legacyData)
        }

        return values
    }

    private static func stringDefaults(from defaults: UserDefaults, key: String, legacyKey: String) -> [String] {
        var values: [String] = []

        if let value = defaults.string(forKey: key) {
            values.append(value)
        }

        if let legacyValue = defaults.string(forKey: legacyKey), !values.contains(legacyValue) {
            values.append(legacyValue)
        }

        return values
    }

    private static func boolDefault(from defaults: UserDefaults, key: String, legacyKey: String) -> Bool? {
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }

        return defaults.object(forKey: legacyKey) as? Bool
    }

    private static func isEnvironmentFlagEnabled(_ key: String, legacyKey: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return [environment[key], environment[legacyKey]].contains { value in
            guard let value else {
                return false
            }

            return ["1", "true", "yes", "on"].contains(
                value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }
    }

    private static func cgEventFlags(from modifierFlags: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags = CGEventFlags()

        if modifierFlags.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifierFlags.contains(.shift) {
            flags.insert(.maskShift)
        }
        if modifierFlags.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifierFlags.contains(.control) {
            flags.insert(.maskControl)
        }

        return flags
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
