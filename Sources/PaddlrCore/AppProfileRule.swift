import Foundation

/// A rule that changes Paddlr behavior when an app is active.
public struct AppProfileRule: Codable, Equatable, Identifiable, Sendable {
    public var bundleIdentifier: String
    public var appName: String
    public var action: AppProfileRuleAction

    public var id: String {
        bundleIdentifier
    }

    public init(
        bundleIdentifier: String,
        appName: String,
        action: AppProfileRuleAction
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.action = action
    }
}

public enum AppProfileRuleAction: Codable, Equatable, Sendable {
    case useProfile(UUID)
    case disableOutput

    public func displayName(profileNameForID: (UUID) -> String?) -> String {
        switch self {
        case .useProfile(let profileID):
            return "Use profile: \(profileNameForID(profileID) ?? "Missing profile")"
        case .disableOutput:
            return "Disable output"
        }
    }
}
