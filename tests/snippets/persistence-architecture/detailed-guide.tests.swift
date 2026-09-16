import Foundation

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

protocol ArchiveItemUseCase {
    func archive(id: Item.ID) async throws
}

nonisolated(unsafe) var repo: (any ItemRepository)!
nonisolated(unsafe) var sut: (any ArchiveItemUseCase)!
