import Foundation
import SwiftData

public struct ItemFilter: Sendable {}

public protocol ItemRepository {
    func fetch(id: Item.ID) async throws -> Item?
    func list(filter: ItemFilter) async throws -> [Item]
    func observe(filter: ItemFilter) -> AsyncStream<[Item]>
    func upsert(_ item: Item) async throws
    func delete(id: Item.ID) async throws
}

public struct Item: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
    public var version: Int
}

@Model
final class ItemEntity {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var version: Int

    init(
        id: UUID, title: String, createdAt: Date, updatedAt: Date, isArchived: Bool, version: Int
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.version = version
    }
}

extension SwiftDataItemRepository {
    func list(filter: ItemFilter) async throws -> [Item] { [] }
    func upsert(_ item: Item) async throws {}
    func delete(id: Item.ID) async throws {}
}

extension ItemEntity {
    convenience init(from item: Item) {
        self.init(
            id: item.id, title: item.title, createdAt: item.createdAt, updatedAt: item.updatedAt,
            isArchived: item.isArchived, version: item.version
        )
    }
}
