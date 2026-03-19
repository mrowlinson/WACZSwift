import Foundation
import Testing

@testable import WACZSwift

@Suite("Hashing")
struct HashingTests {
    @Test("SHA-256 hash of known data")
    func sha256Hash() {
        let data = Data("hello world".utf8)
        let result = hashData(data, using: .sha256)
        #expect(result == "sha256:b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    @Test("MD5 hash of known data")
    func md5Hash() {
        let data = Data("hello world".utf8)
        let result = hashData(data, using: .md5)
        #expect(result == "md5:5eb63bbbe01eeed093cb22bb8f5acdc3")
    }

    @Test("Hash stream matches hash data")
    func hashStreamConsistency() {
        let data = Data("test data for hashing".utf8)
        let directHash = hashData(data, using: .sha256)

        let stream = InputStream(data: data)
        let streamResult = hashStream(stream, using: .sha256)

        #expect(streamResult.digest == directHash)
        #expect(streamResult.size == data.count)
    }

    @Test("Empty data hash")
    func emptyHash() {
        let result = hashData(Data(), using: .sha256)
        #expect(result == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
