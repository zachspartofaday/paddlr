import Foundation

public struct KeyboardOutputSource: Hashable, Sendable {
    public var controllerIdentifier: String
    public var paddle: Paddle

    public init(controllerIdentifier: String, paddle: Paddle) {
        self.controllerIdentifier = controllerIdentifier
        self.paddle = paddle
    }
}

public enum KeyboardOutputCommand: Equatable, Sendable {
    case keyDown(KeyboardMapping)
    case keyUp(KeyboardMapping)
}

/// Tracks posted keyboard state so duplicate paddle mappings share one key-down/key-up pair.
public struct KeyboardOutputSessionTracker: Equatable, Sendable {
    private var postedKeyboardBySource: [KeyboardOutputSource: KeyboardMapping] = [:]

    public init() {}

    public var isEmpty: Bool {
        postedKeyboardBySource.isEmpty
    }

    public mutating func setKeyboard(
        _ mapping: KeyboardMapping,
        isPressed: Bool,
        source: KeyboardOutputSource
    ) -> KeyboardOutputCommand? {
        if isPressed {
            guard postedKeyboardBySource[source] == nil else {
                return nil
            }

            let shouldPostKeyDown = !postedKeyboardBySource.values.contains(mapping)
            postedKeyboardBySource[source] = mapping
            return shouldPostKeyDown ? .keyDown(mapping) : nil
        }

        let postedMapping = postedKeyboardBySource.removeValue(forKey: source) ?? mapping
        let shouldPostKeyUp = !postedKeyboardBySource.values.contains(postedMapping)
        return shouldPostKeyUp ? .keyUp(postedMapping) : nil
    }

    public mutating func releaseAll() -> [KeyboardOutputCommand] {
        guard !postedKeyboardBySource.isEmpty else {
            return []
        }

        let postedKeys = postedKeyboardBySource
        postedKeyboardBySource.removeAll()
        return Self.keyUpCommands(for: Set(postedKeys.values))
    }

    public mutating func releaseAll(for controllerIdentifiers: Set<String>) -> [KeyboardOutputCommand] {
        guard !controllerIdentifiers.isEmpty, !postedKeyboardBySource.isEmpty else {
            return []
        }

        let removedMappings = postedKeyboardBySource.compactMap { source, mapping in
            controllerIdentifiers.contains(source.controllerIdentifier) ? mapping : nil
        }
        postedKeyboardBySource = postedKeyboardBySource.filter { source, _ in
            !controllerIdentifiers.contains(source.controllerIdentifier)
        }

        let releasableMappings = Set(removedMappings).filter { mapping in
            !postedKeyboardBySource.values.contains(mapping)
        }
        return Self.keyUpCommands(for: releasableMappings)
    }

    private static func keyUpCommands(for mappings: Set<KeyboardMapping>) -> [KeyboardOutputCommand] {
        mappings
            .sorted(by: { $0.displayName < $1.displayName })
            .map { .keyUp($0) }
    }
}
