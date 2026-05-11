import Foundation

/// An output action assigned to a paddle.
public enum PaddleAction: Codable, Equatable, Sendable {
    case keyboard(KeyboardMapping)
    case disabled

    public var displayName: String {
        switch self {
        case .keyboard(let mapping):
            return mapping.displayName
        case .disabled:
            return "Disabled"
        }
    }

    public static func keyboard(_ key: SyntheticKey) -> PaddleAction {
        .keyboard(KeyboardMapping(syntheticKey: key))
    }
}
