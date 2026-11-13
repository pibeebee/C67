import Foundation

/// A live page, not a frozen multi-request snapshot. Treat the cursor as opaque.
public struct RepositoryPage<Item: Equatable & Sendable>: Equatable, Sendable {
    public let items: [Item]
    public let nextCursor: String?
    public init(items: [Item], nextCursor: String?) { self.items = items; self.nextCursor = nextCursor }
}
