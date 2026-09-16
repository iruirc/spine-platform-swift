import Foundation

public struct ItemDraft: Sendable {}
public struct ItemDTO: Decodable, Sendable {}
struct Item: Sendable {
    init(dto: ItemDTO) {}
}
protocol ItemsRepository: Sendable {
    func fetchItems() async throws -> [Item]
}
enum APIErrorMapper {
    static func check(_ response: HTTPResponse) throws {}
}
enum ErrorMapper {
    static func toUserMessage(_ error: Error) -> String { "" }
}
enum HTTPClientError: Error {
    case invalidResponse
}
public struct RealtimeEvent: Sendable {}
extension JSONDecoder {
    static var api: JSONDecoder { JSONDecoder() }
}
extension HTTPItemsAPI {
    func createItem(_ draft: ItemDraft) async throws -> ItemDTO { ItemDTO() }
    func deleteItem(id: String) async throws {}
}
extension URLSessionHTTPClient {
    func toURLRequest(_ request: HTTPRequest) throws -> URLRequest { URLRequest(url: request.url) }
}
