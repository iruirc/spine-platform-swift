struct ItemPayloadV1: Codable {
    var a: String
    var b: Int
    var firstName: String
    var lastName: String
}

struct ItemPayloadV2: Codable {
    var a: String
    var b: Int
    var fullName: String
}

struct ItemPayloadV3: Codable {}

enum PayloadError: Error {
    case unknownVersion(Int)
}
