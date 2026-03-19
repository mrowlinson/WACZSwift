import Foundation

public struct DatapackageResource: Codable, Sendable {
    public var name: String
    public var path: String
    public var hash: String
    public var bytes: Int

    public init(name: String, path: String, hash: String, bytes: Int) {
        self.name = name
        self.path = path
        self.hash = hash
        self.bytes = bytes
    }
}
