import Foundation

public struct DatapackageDigest: Codable, Sendable {
    public var path: String
    public var hash: String
    public var signedData: SignedData?

    public init(path: String, hash: String, signedData: SignedData? = nil) {
        self.path = path
        self.hash = hash
        self.signedData = signedData
    }

    public struct SignedData: Codable, Sendable {
        public var hash: String
        public var created: String
        public var software: String?
        public var signature: String?
        public var domain: String?

        // Allow arbitrary additional fields from the signing service
        private var additionalFields: [String: String]?

        public init(hash: String, created: String, software: String? = nil, signature: String? = nil, domain: String? = nil) {
            self.hash = hash
            self.created = created
            self.software = software
            self.signature = signature
            self.domain = domain
        }
    }
}
