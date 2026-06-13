import Foundation

/// Persisted configuration for one physical controller identity.
public struct ControllerConfiguration: Codable, Equatable, Sendable {
    public var identifier: String
    public var productName: String?
    public var displayName: String?
    public var profileID: UUID?
    public var isPinned: Bool
    public var isPrimary: Bool

    public init(
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }
}
