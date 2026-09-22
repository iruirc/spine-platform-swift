struct Cart: Equatable, Sendable {
    static let empty = Cart()
}
enum CheckoutError: Error, Equatable {
    case emptyCart
}
protocol OrderRepositoryProtocol: Sendable {
    func store(_ cart: Cart) throws
}
struct FakeOrderRepository: OrderRepositoryProtocol {
    func store(_ cart: Cart) throws {}
}
struct CheckoutService: Sendable {
    let repository: OrderRepositoryProtocol
    var total: Int { 1 }
    func submit(_ cart: Cart) throws {
        guard cart != .empty else { throw CheckoutError.emptyCart }
        try repository.store(cart)
    }
}
