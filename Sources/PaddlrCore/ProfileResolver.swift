import Foundation

/// Resolves profile and output behavior from app rules, controller defaults, and global output toggles.
public struct ProfileResolver: Sendable {
    public var profiles: [MappingProfile]
    public var appRules: [AppProfileRule]
    public var controllerConfigurations: [ControllerConfiguration]
    public var defaultProfileID: UUID
    public var selectedProfileID: UUID
    public var outputEnabled: Bool
    public var defaultApplicationOutputEnabled: Bool

    public init(
        profiles: [MappingProfile],
        appRules: [AppProfileRule],
        controllerConfigurations: [ControllerConfiguration],
        defaultProfileID: UUID,
        selectedProfileID: UUID,
        outputEnabled: Bool,
        defaultApplicationOutputEnabled: Bool
    ) {
        self.profiles = profiles
        self.appRules = appRules
        self.controllerConfigurations = controllerConfigurations
        self.defaultProfileID = defaultProfileID
        self.selectedProfileID = selectedProfileID
        self.outputEnabled = outputEnabled
        self.defaultApplicationOutputEnabled = defaultApplicationOutputEnabled
    }

    public var selectedProfile: MappingProfile {
        profile(for: selectedProfileID) ?? profiles.first ?? .defaultProfile
    }

    public func appRule(bundleIdentifier: String, controllerIdentifier: String?) -> AppProfileRule? {
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

    public func profileIDForApplication(bundleIdentifier: String?, controllerIdentifier: String?) -> UUID {
        if
            let bundleIdentifier,
            let rule = appRule(bundleIdentifier: bundleIdentifier, controllerIdentifier: controllerIdentifier),
            case .useProfile(let profileID) = rule.action,
            profileExists(profileID)
        {
            return profileID
        }

        if
            let controllerIdentifier,
            let profileID = controllerConfiguration(for: controllerIdentifier)?.profileID,
            profileExists(profileID)
        {
            return profileID
        }

        return validDefaultProfileID()
    }

    public func effectiveProfile(bundleIdentifier: String?, controllerIdentifier: String?) -> MappingProfile {
        profile(for: profileIDForApplication(bundleIdentifier: bundleIdentifier, controllerIdentifier: controllerIdentifier)) ??
            selectedProfile
    }

    public func profileForController(identifier: String, bundleIdentifier: String?) -> MappingProfile {
        if
            let bundleIdentifier,
            let controllerAppRule = appRules.first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.controllerIdentifier == identifier
            }),
            case .useProfile(let profileID) = controllerAppRule.action,
            let profile = profile(for: profileID)
        {
            return profile
        }

        let fallbackProfileID = fallbackProfileIDForUnassignedController(
            identifier: identifier,
            bundleIdentifier: bundleIdentifier
        )
        return profile(for: fallbackProfileID) ?? selectedProfile
    }

    public func effectiveOutputEnabled(bundleIdentifier: String?, controllerIdentifier: String?) -> Bool {
        guard outputEnabled else {
            return false
        }

        guard
            let bundleIdentifier,
            let activeAppRule = appRule(bundleIdentifier: bundleIdentifier, controllerIdentifier: controllerIdentifier)
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

    public func validDefaultProfileID() -> UUID {
        if profileExists(defaultProfileID) {
            return defaultProfileID
        }

        return profiles.first?.id ?? selectedProfileID
    }

    public func profile(for profileID: UUID) -> MappingProfile? {
        profiles.first(where: { $0.id == profileID })
    }

    private func fallbackProfileIDForUnassignedController(identifier: String?, bundleIdentifier: String?) -> UUID {
        if
            let bundleIdentifier,
            let activeAppRule = appRule(bundleIdentifier: bundleIdentifier, controllerIdentifier: identifier),
            case .useProfile(let profileID) = activeAppRule.action,
            profileExists(profileID)
        {
            return profileID
        }

        if
            let identifier,
            let profileID = controllerConfiguration(for: identifier)?.profileID,
            profileExists(profileID)
        {
            return profileID
        }

        return validDefaultProfileID()
    }

    private func profileExists(_ profileID: UUID) -> Bool {
        profiles.contains(where: { $0.id == profileID })
    }

    private func controllerConfiguration(for identifier: String) -> ControllerConfiguration? {
        controllerConfigurations.first(where: { $0.identifier == identifier })
    }
}
