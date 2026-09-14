protocol Greeter: Sendable { func greet(_ name: String) -> String }
struct EnglishGreeter: Greeter { func greet(_ name: String) -> String { "Hello, \(name)" } }
