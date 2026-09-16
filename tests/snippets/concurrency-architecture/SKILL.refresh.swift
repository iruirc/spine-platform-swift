struct Credentials: Sendable {
    let accessToken: String
    let refreshToken: String
}
protocol CredentialStore: Sendable {
    func load() -> Credentials?
    func save(_ credentials: Credentials?)
}
protocol AuthAPI: Sendable {
    func refresh(_ refreshToken: String) async throws -> Credentials
}
enum AuthError: Error {
    case signedOut
}
