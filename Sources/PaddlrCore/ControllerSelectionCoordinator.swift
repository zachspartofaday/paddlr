import Foundation

/// Visible controller row state for menu bar selection controls.
public struct ControllerSelection: Identifiable, Hashable, Sendable {
    public var identifier: String
    public var displayName: String
    public var productName: String
    public var index: Int
    public var isConnected: Bool
    public var isPinned: Bool
    public var isPrimary: Bool
    public var hasCustomDisplayName: Bool

    public var id: String {
        identifier
    }

    public var title: String {
        displayName
    }

    public init(
        identifier: String,
        displayName: String,
        productName: String,
        index: Int,
        isConnected: Bool,
        isPinned: Bool,
        isPrimary: Bool,
        hasCustomDisplayName: Bool
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.productName = productName
        self.index = index
        self.isConnected = isConnected
        self.isPinned = isPinned
        self.isPrimary = isPrimary
        self.hasCustomDisplayName = hasCustomDisplayName
    }
}

public struct ControllerRegistration: Equatable, Sendable {
    public var configurations: [ControllerConfiguration]
    public var newlyAssignedPrimaryIdentifier: String?

    public init(configurations: [ControllerConfiguration], newlyAssignedPrimaryIdentifier: String?) {
        self.configurations = configurations
        self.newlyAssignedPrimaryIdentifier = newlyAssignedPrimaryIdentifier
    }
}

public struct ControllerSelectionState: Equatable, Sendable {
    public var selectedControllerIdentifier: String?
    public var selectionWasUserInitiated: Bool
    public var shouldSyncSelectedProfile: Bool
    public var shouldPublishPressedPaddles: Bool

    public init(
        selectedControllerIdentifier: String?,
        selectionWasUserInitiated: Bool,
        shouldSyncSelectedProfile: Bool,
        shouldPublishPressedPaddles: Bool
    ) {
        self.selectedControllerIdentifier = selectedControllerIdentifier
        self.selectionWasUserInitiated = selectionWasUserInitiated
        self.shouldSyncSelectedProfile = shouldSyncSelectedProfile
        self.shouldPublishPressedPaddles = shouldPublishPressedPaddles
    }
}

/// Deterministic controller naming, visibility, sorting, registration, and fallback selection rules.
public struct ControllerSelectionCoordinator: Sendable {
    public init() {}

    public func visibleSelections(
        configurations: [ControllerConfiguration],
        connectedControllers: [HIDPaddleControllerInfo]
    ) -> [ControllerSelection] {
        let connectedControllersByIdentifier = Dictionary(
            uniqueKeysWithValues: connectedControllers.map { ($0.identifier, $0) }
        )
        let visibleConfigurations = configurations.filter { configuration in
            configuration.isPrimary ||
                configuration.isPinned ||
                connectedControllersByIdentifier[configuration.identifier] != nil
        }

        return visibleConfigurations
            .sorted(by: { controllerConfigurationSort($0, $1, configurations: configurations) })
            .enumerated()
            .map { index, configuration in
                let connectedController = connectedControllersByIdentifier[configuration.identifier]
                let productName = connectedController?.productName ?? configuration.productName ?? "Xbox Wireless Controller"
                let displayName = displayName(
                    for: configuration.identifier,
                    fallback: productName,
                    configurations: configurations
                )
                return ControllerSelection(
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

    public func registerConnectedControllers(
        _ controllers: [HIDPaddleControllerInfo],
        configurations existingConfigurations: [ControllerConfiguration]
    ) -> ControllerRegistration {
        guard !controllers.isEmpty else {
            return ControllerRegistration(configurations: existingConfigurations, newlyAssignedPrimaryIdentifier: nil)
        }

        var configurations = existingConfigurations
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

        return ControllerRegistration(
            configurations: configurations,
            newlyAssignedPrimaryIdentifier: newlyAssignedPrimaryIdentifier
        )
    }

    public func selectionAfterStatusChange(
        selections: [ControllerSelection],
        selectedControllerIdentifier: String?,
        selectionWasUserInitiated: Bool
    ) -> ControllerSelectionState {
        guard let selectedControllerIdentifier else {
            return ControllerSelectionState(
                selectedControllerIdentifier: nil,
                selectionWasUserInitiated: selectionWasUserInitiated,
                shouldSyncSelectedProfile: false,
                shouldPublishPressedPaddles: true
            )
        }

        if let selectedController = selections.first(where: { $0.identifier == selectedControllerIdentifier }) {
            if
                !selectionWasUserInitiated,
                !selectedController.isConnected,
                let firstConnectedController = selections.first(where: \.isConnected)
            {
                return ControllerSelectionState(
                    selectedControllerIdentifier: firstConnectedController.identifier,
                    selectionWasUserInitiated: false,
                    shouldSyncSelectedProfile: true,
                    shouldPublishPressedPaddles: true
                )
            }

            return ControllerSelectionState(
                selectedControllerIdentifier: selectedControllerIdentifier,
                selectionWasUserInitiated: selectionWasUserInitiated,
                shouldSyncSelectedProfile: true,
                shouldPublishPressedPaddles: false
            )
        }

        return ControllerSelectionState(
            selectedControllerIdentifier: selections.first(where: \.isConnected)?.identifier ?? selections.first?.identifier,
            selectionWasUserInitiated: false,
            shouldSyncSelectedProfile: true,
            shouldPublishPressedPaddles: true
        )
    }

    public func defaultSelectedControllerIdentifier(from configurations: [ControllerConfiguration]) -> String? {
        configurations.first(where: \.isPrimary)?.identifier ??
            configurations.first(where: \.isPinned)?.identifier
    }

    public func displayName(
        for controller: HIDPaddleControllerInfo,
        configurations: [ControllerConfiguration]
    ) -> String {
        displayName(for: controller.identifier, fallback: controller.productName, configurations: configurations)
    }

    public func displayName(
        for identifier: String,
        fallback: String,
        configurations: [ControllerConfiguration]
    ) -> String {
        controllerConfiguration(for: identifier, configurations: configurations)?
            .displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? fallback
    }

    private func controllerConfigurationSort(
        _ lhs: ControllerConfiguration,
        _ rhs: ControllerConfiguration,
        configurations: [ControllerConfiguration]
    ) -> Bool {
        if lhs.isPrimary != rhs.isPrimary {
            return lhs.isPrimary
        }

        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }

        let lhsName = displayName(
            for: lhs.identifier,
            fallback: lhs.productName ?? "Xbox Wireless Controller",
            configurations: configurations
        )
        let rhsName = displayName(
            for: rhs.identifier,
            fallback: rhs.productName ?? "Xbox Wireless Controller",
            configurations: configurations
        )
        if lhsName != rhsName {
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        return lhs.identifier < rhs.identifier
    }

    private func controllerConfiguration(
        for identifier: String,
        configurations: [ControllerConfiguration]
    ) -> ControllerConfiguration? {
        configurations.first(where: { $0.identifier == identifier })
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
