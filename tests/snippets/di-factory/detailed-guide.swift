struct User: Equatable, Sendable {
    static let fixture = User()
}
enum ProfileState: Equatable {
    case idle
    case loaded(User)
    case error
}
protocol UserServiceProtocol: Sendable {
    func fetchCurrent() async throws -> User
}
struct MockUserService: UserServiceProtocol {
    let result: Result<User, Error>
    func fetchCurrent() async throws -> User { try result.get() }
}
@MainActor
final class ProfileViewModel {
    private(set) var state: ProfileState = .idle
    private let userService: UserServiceProtocol
    init(userService: UserServiceProtocol) { self.userService = userService }
    func load() async {
        do { state = .loaded(try await userService.fetchCurrent()) } catch { state = .error }
    }
}
