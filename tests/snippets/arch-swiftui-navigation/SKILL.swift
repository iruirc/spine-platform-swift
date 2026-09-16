struct Item: Hashable {
    let id: String
}
struct Profile: Hashable {
    let id: String
}
struct FullScreenRoute {}
enum Route {
    case item(id: String)
    case profile(userId: String)
    case settings
}
