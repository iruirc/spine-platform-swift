import Foundation

struct Item: Sendable {}
struct ItemCellModel: Identifiable {
    let id = UUID()
    let title = ""
    init(_ item: Item) {}
}
protocol FeatureServiceProtocol: Sendable {
    func fetchItems() async throws -> [Item]
}
