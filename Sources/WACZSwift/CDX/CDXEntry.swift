import Foundation

public struct CDXEntry: Sendable, Comparable {
    public let surt: String
    public let timestamp: String
    public let url: String
    public let mime: String
    public let status: String
    public let digest: String
    public let length: String
    public let offset: String
    public let filename: String

    public static func < (lhs: CDXEntry, rhs: CDXEntry) -> Bool {
        if lhs.surt == rhs.surt {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.surt < rhs.surt
    }

    /// Format as a CDXJ line: "{surt} {timestamp} {json}\n"
    public func toCDXJLine() -> String {
        var dict: [String: String] = [
            "url": url,
            "mime": mime,
            "status": status,
            "digest": digest,
            "length": length,
            "offset": offset,
            "filename": filename,
        ]

        // Produce sorted JSON for deterministic output
        let sortedKeys = dict.keys.sorted()
        let jsonParts = sortedKeys.map { key -> String in
            let value = dict[key]!
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(key)\":\"\(escaped)\""
        }
        let json = "{\(jsonParts.joined(separator: ","))}"

        return "\(surt) \(timestamp) \(json)\n"
    }
}
