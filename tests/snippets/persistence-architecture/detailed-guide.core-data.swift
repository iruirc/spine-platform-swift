import CoreData

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

enum RepositoryError: Error {
    case conflict(id: UUID)
}

@objc(ItemEntity)
final class ItemEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var isArchived: Bool
    @NSManaged var version: Int64

    @nonobjc class func fetchRequest() -> NSFetchRequest<ItemEntity> {
        NSFetchRequest<ItemEntity>(entityName: "ItemEntity")
    }
}

extension CoreDataItemRepository {
    static func fill(_ entity: ItemEntity, from item: Item) {}
    func list(filter: ItemFilter) async throws -> [Item] { [] }
    func observe(filter: ItemFilter) -> AsyncStream<[Item]> { AsyncStream { $0.finish() } }
    func delete(id: Item.ID) async throws {}
}
