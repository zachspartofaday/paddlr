import Foundation

/// A named set of paddle output actions.
public struct MappingProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var actions: [Paddle: PaddleAction]

    public init(
        id: UUID = UUID(),
        name: String,
        actions: [Paddle: PaddleAction]
    ) {
        self.id = id
        self.name = name
        self.actions = Self.actionsWithDefaults(actions)
    }

    public func action(for paddle: Paddle) -> PaddleAction {
        actions[paddle] ?? Self.defaultActions[paddle] ?? .disabled
    }

    public func withAction(_ action: PaddleAction, for paddle: Paddle) -> MappingProfile {
        var copy = self
        copy.actions[paddle] = action
        copy.actions = Self.actionsWithDefaults(copy.actions)
        return copy
    }

    public func withName(_ name: String) -> MappingProfile {
        var copy = self
        copy.name = name
        return copy
    }

    public func resetToDefaultActions() -> MappingProfile {
        var copy = self
        copy.actions = Self.defaultActions
        return copy
    }

    public static let defaultProfileName = "Default"

    public static var defaultProfile: MappingProfile {
        MappingProfile(name: defaultProfileName, actions: defaultActions)
    }

    public static func defaultProfile(legacySyntheticMappings: [Paddle: SyntheticKey]) -> MappingProfile {
        var actions = defaultActions

        for (paddle, key) in legacySyntheticMappings {
            actions[paddle] = .keyboard(key)
        }

        return MappingProfile(name: defaultProfileName, actions: actions)
    }

    public static let defaultActions: [Paddle: PaddleAction] = [
        .one: .keyboard(.f13),
        .two: .keyboard(.f14),
        .three: .keyboard(.f15),
        .four: .keyboard(.f16)
    ]

    private static func actionsWithDefaults(_ actions: [Paddle: PaddleAction]) -> [Paddle: PaddleAction] {
        var merged = defaultActions

        for (paddle, action) in actions {
            merged[paddle] = action
        }

        return merged
    }
}
