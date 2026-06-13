import AppKit
import Combine
import Darwin
import PaddlrCore
import Foundation

struct MenuBarStatusItemState: Equatable, Hashable {
    var isEnabledForCurrentApplication: Bool
    var isControllerConnected: Bool
}

struct PermissionRestartPrompt: Equatable, Hashable {
    var messageText: String
    var informativeText: String
}

typealias MenuBarControllerSelection = ControllerSelection
typealias MenuBarPinnedApplication = PinnedApplication

/// Observable state and orchestration for the Phase 3/4 menu bar app.
final class MenuBarMapperModel: ObservableObject {
    @Published var outputEnabled: Bool {
        didSet {
            guard outputEnabled != oldValue else {
                return
            }

            settingsStore.writeOutputEnabled(outputEnabled)
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

            settingsStore.writeDefaultApplicationOutputEnabled(defaultApplicationOutputEnabled)
            appendEvent("[Output] Default application output \(defaultApplicationOutputEnabled ? "enabled" : "disabled").")

            if !defaultApplicationOutputEnabled {
                releasePostedKeysForControllersWithDisabledOutput(reason: "default application output disabled")
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
                settingsStore.writeSelectedProfileID(selectedProfileID)
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

    private static let maxObservedApplications = 3
    private static let deviceStatusPollInterval: TimeInterval = 3
    private static let debugConsoleLoggingEnabled = MenuBarMapperModel.isEnvironmentFlagEnabled(
        "PADDLR_DEBUG_LOG",
        legacyKey: "ELITEMAPPER_DEBUG_LOG"
    )

    private let settingsStore: PaddlrSettingsStore
    private let controllerSelectionCoordinator = ControllerSelectionCoordinator()
    private let monitorStatusPresenter = MonitorStatusPresenter()
    private var monitor: HIDPaddleMonitor?
    private var frontmostAppMonitor: FrontmostAppMonitor?
    private var keyCaptureMonitor: Any?
    private var deviceStatusPollTimer: Timer?
    private var recentEventLog = RecentEventLogModel(maxEvents: 40)
    private var defaultSelectedProfileID: UUID
    private var isSyncingSelectedProfileFromController = false
    private var selectedControllerSelectionWasUserInitiated = false
    private var permissionCoordinator = PermissionCoordinator()
    private var livePressedPaddlesByController: [String: Set<Paddle>] = [:]
    private var keyboardOutputSessionTracker = KeyboardOutputSessionTracker()

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

        return profileResolver.appRule(bundleIdentifier: ruleKey, controllerIdentifier: selectedControllerIdentifier)
    }

    var effectiveProfile: MappingProfile {
        profileResolver.effectiveProfile(
            bundleIdentifier: frontmostApplication?.ruleKey,
            controllerIdentifier: selectedControllerIdentifier
        )
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
        controllerSelectionCoordinator.visibleSelections(
            configurations: controllerConfigurations,
            connectedControllers: paddleDeviceStatus.controllers
        )
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

    private var profileResolver: ProfileResolver {
        ProfileResolver(
            profiles: profiles,
            appRules: appRules,
            controllerConfigurations: controllerConfigurations,
            defaultProfileID: defaultSelectedProfileID,
            selectedProfileID: selectedProfileID,
            outputEnabled: outputEnabled,
            defaultApplicationOutputEnabled: defaultApplicationOutputEnabled
        )
    }

    init(defaults: UserDefaults = .standard) {
        let settingsStore = PaddlrSettingsStore(defaults: defaults)
        self.settingsStore = settingsStore

        let loadedProfiles = settingsStore.loadProfiles()
        let resolvedProfiles = loadedProfiles.isEmpty ? [MappingProfile.defaultProfile] : loadedProfiles
        self.profiles = resolvedProfiles
        self.appRules = settingsStore.loadAppRules()
        self.pinnedApplications = settingsStore.loadPinnedApplications()
        let loadedControllerConfigurations = settingsStore.loadControllerConfigurations()
        self.controllerConfigurations = loadedControllerConfigurations
        let restoredControllerIdentifier = controllerSelectionCoordinator.defaultSelectedControllerIdentifier(
            from: loadedControllerConfigurations
        )
        self.selectedControllerIdentifier = restoredControllerIdentifier

        let initialSelectedProfileID = settingsStore.loadSelectedProfileID(availableProfiles: resolvedProfiles)
        self.selectedProfileID = initialSelectedProfileID
        self.defaultSelectedProfileID = initialSelectedProfileID

        self.outputEnabled = settingsStore.loadOutputEnabled()
        self.defaultApplicationOutputEnabled = settingsStore.loadDefaultApplicationOutputEnabled()
        self.accessibilityTrusted = KeyboardOutputSynthesizer.isAccessibilityTrusted(prompt: false)
        self.inputMonitoringTrusted = HIDPaddleMonitor.isInputMonitoringTrusted(prompt: false)

        settingsStore.writeOutputEnabled(outputEnabled)
        settingsStore.writeDefaultApplicationOutputEnabled(defaultApplicationOutputEnabled)
        persistProfiles()
        persistAppRules()
        persistPinnedApplications()
        persistControllerConfigurations()
        settingsStore.writeSelectedProfileID(defaultSelectedProfileID)

        appendEvent("[App] Paddlr menu bar UI started.")
        appendEvent("[Profile] Selected \(selectedProfileName).")
        appendEvent("[Output] Keyboard output \(outputEnabled ? "enabled" : "disabled").")
        appendEvent("[Output] Default application output \(defaultApplicationOutputEnabled ? "enabled" : "disabled").")
        appendEvent("[Accessibility] Permission is \(accessibilityTrusted ? "trusted" : "not trusted").")
        appendEvent("[ControllerInputAccess] Permission is \(inputMonitoringTrusted ? "ready" : "not ready").")
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
        if let events = recentEventLog.setPublishingEnabled(isVisible) {
            recentEvents = events
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
        if prompt {
            armPermissionRestartPrompt(for: .accessibility)
        }

        accessibilityTrusted = KeyboardOutputSynthesizer.isAccessibilityTrusted(prompt: prompt)
        appendEvent("[Accessibility] Permission is \(accessibilityTrusted ? "trusted" : "not trusted").")
    }

    func refreshInputMonitoringTrust(prompt: Bool) {
        if prompt {
            armPermissionRestartPrompt(for: .controllerInputAccess)
        }

        inputMonitoringTrusted = HIDPaddleMonitor.isInputMonitoringTrusted(prompt: prompt)
        appendEvent("[ControllerInputAccess] Permission is \(inputMonitoringTrusted ? "ready" : "not ready").")

        if inputMonitoringTrusted {
            startMonitor()
        } else if prompt {
            monitorStatus = "Controller input access needed."
            appendEvent("[ControllerInputAccess] Approve Paddlr in System Settings, then click the button again if needed.")
        }
    }

    func noteApplicationDidResignActive() {
        permissionCoordinator.noteApplicationDidResignActive()
    }

    func consumePermissionRestartPromptAfterActivation() -> PermissionRestartPrompt? {
        guard permissionCoordinator.hasPendingPrompt else {
            return nil
        }

        refreshPermissionTrustAfterReturn()

        guard permissionCoordinator.consumeRestartPromptAfterActivation() else {
            return nil
        }

        return PermissionRestartPrompt(
            messageText: "Restart Paddlr to finish permission changes",
            informativeText: "macOS permission changes may not take effect in a running app immediately. Click Restart Paddlr to quit and reopen automatically."
        )
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
            settingsStore.writeSelectedProfileID(profileID)
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
        profileResolver.appRule(bundleIdentifier: bundleIdentifier, controllerIdentifier: controllerIdentifier)
    }

    func profileIDForApplication(bundleIdentifier: String?, controllerIdentifier: String?) -> UUID {
        profileResolver.profileIDForApplication(
            bundleIdentifier: bundleIdentifier,
            controllerIdentifier: controllerIdentifier
        )
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

    private func armPermissionRestartPrompt(for kind: PermissionRestartPromptKind) {
        permissionCoordinator.armRestartPrompt(for: kind)
    }

    private func refreshPermissionTrustAfterReturn() {
        accessibilityTrusted = KeyboardOutputSynthesizer.isAccessibilityTrusted(prompt: false)
        inputMonitoringTrusted = HIDPaddleMonitor.isInputMonitoringTrusted(prompt: false)
        appendEvent("[Accessibility] Permission is \(accessibilityTrusted ? "trusted" : "not trusted").")
        appendEvent("[ControllerInputAccess] Permission is \(inputMonitoringTrusted ? "ready" : "not ready").")

        if inputMonitoringTrusted {
            startMonitor()
        } else {
            updateStatusItemState()
        }
    }

    private func startMonitor() {
        inputMonitoringTrusted = HIDPaddleMonitor.isInputMonitoringTrusted(prompt: false)
        guard inputMonitoringTrusted else {
            monitor?.stop()
            monitor = nil
            clearPressedPaddles()
            paddleDeviceStatus = HIDPaddleDeviceStatus(isConnected: false, deviceName: nil)
            monitorStatus = "Controller input access needed."
            appendEvent("[IOHID] Waiting for controller input access before starting controller detection.")
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
        let source = KeyboardOutputSource(controllerIdentifier: controllerIdentifier, paddle: paddle)
        if let command = keyboardOutputSessionTracker.setKeyboard(mapping, isPressed: isPressed, source: source) {
            performKeyboardOutputCommand(command)
        }
    }

    private func releasePostedKeys(for controllerIdentifiers: Set<String>, reason: String) {
        let commands = keyboardOutputSessionTracker.releaseAll(for: controllerIdentifiers)
        for command in commands {
            performKeyboardOutputCommand(command)
            appendReleaseEvent(for: command, reason: reason)
        }
    }

    private func releasePostedKeysForControllersWithDisabledOutput(reason: String) {
        let disabledControllerIdentifiers = Set(livePressedPaddlesByController.keys.filter {
            !effectiveOutputEnabled(forControllerIdentifier: $0)
        })
        releasePostedKeys(for: disabledControllerIdentifiers, reason: reason)
    }

    private func releasePostedKeys(reason: String) {
        let commands = keyboardOutputSessionTracker.releaseAll()
        for command in commands {
            performKeyboardOutputCommand(command)
            appendReleaseEvent(for: command, reason: reason)
        }
    }

    private func performKeyboardOutputCommand(_ command: KeyboardOutputCommand) {
        switch command {
        case .keyDown(let mapping):
            synthesizer.setKeyboard(mapping, isPressed: true)
        case .keyUp(let mapping):
            synthesizer.setKeyboard(mapping, isPressed: false)
        }
    }

    private func appendReleaseEvent(for command: KeyboardOutputCommand, reason: String) {
        if case .keyUp(let mapping) = command {
            appendEvent("[Output] Released \(mapping.displayName) due to \(reason).")
        }
    }

    private func registerConnectedControllers(_ controllers: [HIDPaddleControllerInfo]) {
        let registration = controllerSelectionCoordinator.registerConnectedControllers(
            controllers,
            configurations: controllerConfigurations
        )

        if registration.configurations != controllerConfigurations {
            controllerConfigurations = registration.configurations
            persistControllerConfigurations()
        }

        if selectedControllerIdentifier == nil, let newlyAssignedPrimaryIdentifier = registration.newlyAssignedPrimaryIdentifier {
            selectedControllerSelectionWasUserInitiated = false
            selectedControllerIdentifier = newlyAssignedPrimaryIdentifier
            syncSelectedProfileForSelectedController()
        }
    }

    private func syncSelectedControllerAfterStatusChange() {
        let state = controllerSelectionCoordinator.selectionAfterStatusChange(
            selections: connectedControllerSelections,
            selectedControllerIdentifier: selectedControllerIdentifier,
            selectionWasUserInitiated: selectedControllerSelectionWasUserInitiated
        )

        selectedControllerSelectionWasUserInitiated = state.selectionWasUserInitiated
        selectedControllerIdentifier = state.selectedControllerIdentifier

        if state.shouldSyncSelectedProfile {
            syncSelectedProfileForSelectedController()
        }

        if state.shouldPublishPressedPaddles {
            publishPressedPaddlesIfVisible()
        }
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
        profileResolver.profileForController(identifier: identifier, bundleIdentifier: frontmostApplication?.ruleKey)
    }

    private func effectiveOutputEnabled(forControllerIdentifier controllerIdentifier: String?) -> Bool {
        profileResolver.effectiveOutputEnabled(
            bundleIdentifier: frontmostApplication?.ruleKey,
            controllerIdentifier: controllerIdentifier
        )
    }

    private func controllerDisplayName(for controller: HIDPaddleControllerInfo) -> String {
        controllerSelectionCoordinator.displayName(for: controller, configurations: controllerConfigurations)
    }

    private func controllerDisplayName(for identifier: String, fallback: String) -> String {
        controllerSelectionCoordinator.displayName(
            for: identifier,
            fallback: fallback,
            configurations: controllerConfigurations
        )
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
            try settingsStore.writeProfiles(profiles)
        } catch {
            appendEvent("[Profile] Failed to persist profiles: \(error.localizedDescription)")
        }
    }

    private func persistAppRules() {
        do {
            try settingsStore.writeAppRules(appRules)
        } catch {
            appendEvent("[AppRule] Failed to persist app rules: \(error.localizedDescription)")
        }
    }

    private func persistPinnedApplications() {
        do {
            try settingsStore.writePinnedApplications(pinnedApplications)
        } catch {
            appendEvent("[App] Failed to persist pinned apps: \(error.localizedDescription)")
        }
    }

    private func persistControllerConfigurations() {
        do {
            try settingsStore.writeControllerConfigurations(controllerConfigurations)
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
        if let events = recentEventLog.append(message) {
            recentEvents = events
        }
    }

    private func clearPressedPaddles() {
        livePressedPaddlesByController.removeAll()
        publishPressedPaddlesIfVisible()
    }

    private func publishPressedPaddlesIfVisible() {
        guard recentEventLog.isPublishing else {
            return
        }

        let visiblePressedPaddles = selectedControllerPressedPaddles
        guard pressedPaddles != visiblePressedPaddles else {
            return
        }

        pressedPaddles = visiblePressedPaddles
    }

    private func updateMonitorStatus(from message: String) {
        guard let presentation = monitorStatusPresenter.presentation(for: message, paddleDeviceStatus: paddleDeviceStatus) else {
            return
        }

        monitorStatus = presentation.monitorStatus
        if let status = presentation.paddleDeviceStatus {
            paddleDeviceStatus = status
        }
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
