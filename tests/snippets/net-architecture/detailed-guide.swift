import Foundation

enum HTTPClientError: Error {
    case invalidResponse
}
extension URLSessionHTTPClient {
    func toURLRequest(_ request: HTTPRequest) throws -> URLRequest { URLRequest(url: request.url) }
}
