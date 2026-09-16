import Foundation

struct Item: Sendable {
    let id: String
}
struct ItemCellModel: Identifiable {
    let id = UUID()
    let title = ""
    init(_ item: Item) {}
}
protocol FeatureServiceProtocol: Sendable {
    func fetchItems() async throws -> [Item]
}
final class MockFeatureService: FeatureServiceProtocol, @unchecked Sendable {
    var stubbedItems: [Item] = []
    var shouldFail = false
    func fetchItems() async throws -> [Item] {
        if shouldFail { throw URLError(.badServerResponse) }
        return stubbedItems
    }
}
