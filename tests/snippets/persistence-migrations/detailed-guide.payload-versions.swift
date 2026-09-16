struct PayloadV1: Codable {
    var a: String
    var b: Int
    var firstName: String
    var lastName: String
}

struct PayloadV2: Codable {
    var a: String
    var b: Int
    var fullName: String
}

struct PayloadV3: Codable {}

enum PayloadError: Error {
    case unknownVersion(Int)
}
