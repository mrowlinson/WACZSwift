import CryptoKit
import Foundation

public struct HashResult: Sendable {
    public let size: Int
    public let digest: String
}

public func hashStream(_ stream: InputStream, using hashType: HashType = .sha256) -> HashResult {
    stream.open()
    defer { stream.close() }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var size = 0

    switch hashType {
    case .sha256:
        var hasher = SHA256()
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            size += bytesRead
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: bytesRead))
        }
        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return HashResult(size: size, digest: "\(hashType.rawValue):\(hex)")

    case .md5:
        var hasher = Insecure.MD5()
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            size += bytesRead
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: bytesRead))
        }
        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return HashResult(size: size, digest: "\(hashType.rawValue):\(hex)")
    }
}

public func hashData(_ data: Data, using hashType: HashType = .sha256) -> String {
    switch hashType {
    case .sha256:
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hashType.rawValue):\(hex)"
    case .md5:
        let digest = Insecure.MD5.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hashType.rawValue):\(hex)"
    }
}

public func hashFile(at url: URL, using hashType: HashType = .sha256) throws -> HashResult {
    guard let stream = InputStream(url: url) else {
        throw WACZError.fileNotFound(url.path)
    }
    return hashStream(stream, using: hashType)
}

public enum WACZError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case invalidWARC(String)
    case invalidCDX(String)
    case invalidWACZ(String)
    case invalidDatapackage(String)
    case validationFailed(String)
    case signingFailed(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .invalidWARC(let msg): return "Invalid WARC: \(msg)"
        case .invalidCDX(let msg): return "Invalid CDX: \(msg)"
        case .invalidWACZ(let msg): return "Invalid WACZ: \(msg)"
        case .invalidDatapackage(let msg): return "Invalid datapackage: \(msg)"
        case .validationFailed(let msg): return "Validation failed: \(msg)"
        case .signingFailed(let msg): return "Signing failed: \(msg)"
        }
    }
}
