import GameController

/// The four back paddles on an Xbox Elite Series 2 controller.
public enum Paddle: String, CaseIterable, Codable, Sendable {
    case one = "P1"
    case two = "P2"
    case three = "P3"
    case four = "P4"

    /// Short label used in CLI output.
    public var consoleName: String {
        rawValue
    }

    /// Human-readable label used in the menu bar UI.
    public var displayName: String {
        switch self {
        case .one:
            return "Paddle 1"
        case .two:
            return "Paddle 2"
        case .three:
            return "Paddle 3"
        case .four:
            return "Paddle 4"
        }
    }

    /// Apple's GameController input name for this paddle.
    public var gameControllerInputName: String {
        switch self {
        case .one:
            return GCInputXboxPaddleOne
        case .two:
            return GCInputXboxPaddleTwo
        case .three:
            return GCInputXboxPaddleThree
        case .four:
            return GCInputXboxPaddleFour
        }
    }
}
