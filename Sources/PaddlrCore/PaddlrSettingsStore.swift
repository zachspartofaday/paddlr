import Foundation

public struct PinnedApplication: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var bundleIdentifier: String
    public var appName: String

    public var id: String {
        bundleIdentifier
    }

    public init(bundleIdentifier: String, appName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}

/// UserDefaults-backed storage for Paddlr profiles, app rules, controller settings, and output toggles.
public struct PaddlrSettingsStore {
    public static let outputEnabledDefaultsKey = "com.paddlr.phase3.outputEnabled"
    public static let legacyOutputEnabledDefaultsKey = "com.elitemapper.phase3.outputEnabled"
    public static let defaultApplicationOutputEnabledDefaultsKey = "com.paddlr.phase4.defaultApplicationOutputEnabled"
    public static let legacyDefaultApplicationOutputEnabledDefaultsKey = "com.elitemapper.phase4.defaultApplicationOutputEnabled"
    public static let mappingDefaultsPrefix = "com.paddlr.phase3.mapping."
    public static let legacyMappingDefaultsPrefix = "com.elitemapper.phase3.mapping."
    public static let profilesDefaultsKey = "com.paddlr.phase4.profiles.v1"
    public static let legacyProfilesDefaultsKey = "com.elitemapper.phase4.profiles.v1"
    public static let selectedProfileIDDefaultsKey = "com.paddlr.phase4.selectedProfileID"
    public static let legacySelectedProfileIDDefaultsKey = "com.elitemapper.phase4.selectedProfileID"
    public static let appRulesDefaultsKey = "com.paddlr.phase4.appRules.v1"
    public static let legacyAppRulesDefaultsKey = "com.elitemapper.phase4.appRules.v1"
    public static let pinnedApplicationsDefaultsKey = "com.paddlr.phase4.pinnedApplications.v1"
    public static let controllerConfigurationsDefaultsKey = "com.paddlr.phase5.controllerConfigurations.v1"
    public static let legacyControllerConfigurationsDefaultsKey = "com.elitemapper.phase5.controllerConfigurations.v1"

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadProfiles() -> [MappingProfile] {
        for data in dataDefaults(key: Self.profilesDefaultsKey, legacyKey: Self.legacyProfilesDefaultsKey) {
            guard
                let decodedProfiles = try? Self.decoder.decode([MappingProfile].self, from: data),
                !decodedProfiles.isEmpty
            else {
                continue
            }

            return Self.normalizeDefaultProfileName(
                decodedProfiles.map { MappingProfile(id: $0.id, name: $0.name, actions: $0.actions) }
            )
        }

        let legacyMappings = loadLegacySyntheticMappings()
        return [MappingProfile.defaultProfile(legacySyntheticMappings: legacyMappings)]
    }

    public func loadSelectedProfileID(availableProfiles profiles: [MappingProfile]) -> UUID {
        let savedSelectedProfileID = stringDefaults(
            key: Self.selectedProfileIDDefaultsKey,
            legacyKey: Self.legacySelectedProfileIDDefaultsKey
        )
        .compactMap(UUID.init(uuidString:))
        .first
        let fallbackSelectedProfileID = profiles.first?.id ?? MappingProfile.defaultProfile.id

        return savedSelectedProfileID.flatMap { savedID in
            profiles.contains(where: { $0.id == savedID }) ? savedID : nil
        } ?? fallbackSelectedProfileID
    }

    public func loadAppRules() -> [AppProfileRule] {
        for data in dataDefaults(key: Self.appRulesDefaultsKey, legacyKey: Self.legacyAppRulesDefaultsKey) {
            if let rules = try? Self.decoder.decode([AppProfileRule].self, from: data) {
                return rules
            }
        }

        return []
    }

    public func loadPinnedApplications() -> [PinnedApplication] {
        guard
            let data = defaults.data(forKey: Self.pinnedApplicationsDefaultsKey),
            let pinnedApplications = try? Self.decoder.decode([PinnedApplication].self, from: data)
        else {
            return []
        }

        return pinnedApplications
    }

    public func loadControllerConfigurations() -> [ControllerConfiguration] {
        for data in dataDefaults(
            key: Self.controllerConfigurationsDefaultsKey,
            legacyKey: Self.legacyControllerConfigurationsDefaultsKey
        ) {
            if let configurations = try? Self.decoder.decode([ControllerConfiguration].self, from: data) {
                return configurations
            }
        }

        return []
    }

    public func loadOutputEnabled() -> Bool {
        boolDefault(key: Self.outputEnabledDefaultsKey, legacyKey: Self.legacyOutputEnabledDefaultsKey) ?? true
    }

    public func loadDefaultApplicationOutputEnabled() -> Bool {
        boolDefault(
            key: Self.defaultApplicationOutputEnabledDefaultsKey,
            legacyKey: Self.legacyDefaultApplicationOutputEnabledDefaultsKey
        ) ?? true
    }

    public func writeProfiles(_ profiles: [MappingProfile]) throws {
        let data = try Self.encoder.encode(profiles)
        defaults.set(data, forKey: Self.profilesDefaultsKey)
    }

    public func writeAppRules(_ appRules: [AppProfileRule]) throws {
        let data = try Self.encoder.encode(appRules)
        defaults.set(data, forKey: Self.appRulesDefaultsKey)
    }

    public func writePinnedApplications(_ pinnedApplications: [PinnedApplication]) throws {
        let data = try Self.encoder.encode(pinnedApplications)
        defaults.set(data, forKey: Self.pinnedApplicationsDefaultsKey)
    }

    public func writeControllerConfigurations(_ configurations: [ControllerConfiguration]) throws {
        let data = try Self.encoder.encode(configurations)
        defaults.set(data, forKey: Self.controllerConfigurationsDefaultsKey)
    }

    public func writeSelectedProfileID(_ profileID: UUID) {
        defaults.set(profileID.uuidString, forKey: Self.selectedProfileIDDefaultsKey)
    }

    public func writeOutputEnabled(_ outputEnabled: Bool) {
        defaults.set(outputEnabled, forKey: Self.outputEnabledDefaultsKey)
    }

    public func writeDefaultApplicationOutputEnabled(_ outputEnabled: Bool) {
        defaults.set(outputEnabled, forKey: Self.defaultApplicationOutputEnabledDefaultsKey)
    }

    public static func mappingDefaultsKey(for paddle: Paddle) -> String {
        "\(mappingDefaultsPrefix)\(paddle.rawValue)"
    }

    public static func legacyMappingDefaultsKey(for paddle: Paddle) -> String {
        "\(legacyMappingDefaultsPrefix)\(paddle.rawValue)"
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

    private func loadLegacySyntheticMappings() -> [Paddle: SyntheticKey] {
        var mappings: [Paddle: SyntheticKey] = [:]

        for paddle in Paddle.allCases {
            guard let key = stringDefaults(
                key: Self.mappingDefaultsKey(for: paddle),
                legacyKey: Self.legacyMappingDefaultsKey(for: paddle)
            )
            .compactMap(SyntheticKey.init(rawValue:))
            .first else {
                continue
            }

            mappings[paddle] = key
        }

        return mappings
    }

    private func dataDefaults(key: String, legacyKey: String) -> [Data] {
        var values: [Data] = []

        if let data = defaults.data(forKey: key) {
            values.append(data)
        }

        if let legacyData = defaults.data(forKey: legacyKey), !values.contains(legacyData) {
            values.append(legacyData)
        }

        return values
    }

    private func stringDefaults(key: String, legacyKey: String) -> [String] {
        var values: [String] = []

        if let value = defaults.string(forKey: key) {
            values.append(value)
        }

        if let legacyValue = defaults.string(forKey: legacyKey), !values.contains(legacyValue) {
            values.append(legacyValue)
        }

        return values
    }

    private func boolDefault(key: String, legacyKey: String) -> Bool? {
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }

        return defaults.object(forKey: legacyKey) as? Bool
    }
}
