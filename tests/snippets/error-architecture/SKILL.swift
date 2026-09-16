import Foundation

struct Item: Sendable {}
struct ItemDTO: Decodable, Sendable {
    func toDomain() -> Item { Item() }
}
struct HTTPError: Error {
    let statusCode: Int
}
protocol HTTPClient: Sendable {
    func get<T: Decodable & Sendable>(_ path: String) async throws -> T
}
enum L10n {
    enum Item {
        static let notFoundTitle = ""
        static let notFoundBody = ""
    }
    enum Auth {
        static let requiredTitle = ""
        static let requiredBody = ""
    }
    enum Common {
        static let temporaryProblemTitle = ""
        static let tryAgain = ""
        static let errorTitle = ""
        static let unexpected = ""
    }
}
extension FeedViewModel {
    func load() async {}
}
