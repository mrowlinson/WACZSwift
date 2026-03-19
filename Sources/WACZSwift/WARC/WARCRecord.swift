import Foundation

public struct WARCRecord: Sendable {
    public let headers: [String: String]
    public let contentBlock: Data

    // MARK: - Core properties

    public var recordType: WARCRecordType? {
        guard let typeStr = headers["WARC-Type"] else { return nil }
        return WARCRecordType(rawValue: typeStr)
    }

    public var recordID: String? {
        headers["WARC-Record-ID"]
    }

    public var targetURI: String? {
        headers["WARC-Target-URI"]
    }

    public var date: Date? {
        guard let dateStr = headers["WARC-Date"] else { return nil }
        return WARCDate.date(from: dateStr)
    }

    public var contentType: String? {
        headers["Content-Type"]
    }

    public var contentLength: Int? {
        guard let lenStr = headers["Content-Length"] else { return nil }
        return Int(lenStr)
    }

    // MARK: - Digest properties

    public var payloadDigest: String? {
        headers["WARC-Payload-Digest"]
    }

    public var blockDigest: String? {
        headers["WARC-Block-Digest"]
    }

    // MARK: - Optional WARC header accessors

    public var profile: String? {
        headers["WARC-Profile"]
    }

    public var ipAddress: String? {
        headers["WARC-IP-Address"]
    }

    public var truncated: WARCTruncatedReason? {
        guard let val = headers["WARC-Truncated"] else { return nil }
        return WARCTruncatedReason(rawValue: val)
    }

    public var concurrentTo: String? {
        headers["WARC-Concurrent-To"]
    }

    public var refersTo: String? {
        headers["WARC-Refers-To"]
    }

    public var refersToTargetURI: String? {
        headers["WARC-Refers-To-Target-URI"]
    }

    public var refersToDate: Date? {
        guard let dateStr = headers["WARC-Refers-To-Date"] else { return nil }
        return WARCDate.date(from: dateStr)
    }

    public var warcinfoID: String? {
        headers["WARC-Warcinfo-ID"]
    }

    public var warcFilename: String? {
        headers["WARC-Filename"]
    }

    public var identifiedPayloadType: String? {
        headers["WARC-Identified-Payload-Type"]
    }

    public var segmentNumber: Int? {
        guard let val = headers["WARC-Segment-Number"] else { return nil }
        return Int(val)
    }

    public var segmentOriginID: String? {
        headers["WARC-Segment-Origin-ID"]
    }

    public var segmentTotalLength: Int? {
        guard let val = headers["WARC-Segment-Total-Length"] else { return nil }
        return Int(val)
    }

    // MARK: - Helpers

    /// Generate a UUID-based WARC record ID.
    public static func generateRecordID() -> String {
        "<urn:uuid:\(UUID().uuidString.lowercased())>"
    }

    /// For response records, parse the HTTP status line and headers from the content block.
    /// Returns (statusCode, httpHeaders, bodyData).
    public func parseHTTPContent() -> (statusCode: Int, headers: [String: String], body: Data)? {
        guard let type = recordType,
              type == .response || type == .request
        else {
            return nil
        }

        // Find the blank line separating HTTP headers from body
        let crlfcrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let lflf = Data([0x0A, 0x0A])

        var headerEndRange: Range<Data.Index>?
        var separatorLength = 4

        if let range = contentBlock.range(of: crlfcrlf) {
            headerEndRange = range
        } else if let range = contentBlock.range(of: lflf) {
            headerEndRange = range
            separatorLength = 2
        }

        guard let endRange = headerEndRange else { return nil }

        let headerData = contentBlock[contentBlock.startIndex..<endRange.lowerBound]
        let bodyData = contentBlock[endRange.lowerBound.advanced(by: separatorLength)...]

        guard let headerStr = String(data: headerData, encoding: .utf8) ?? String(data: headerData, encoding: .ascii) else {
            return nil
        }

        let lines = headerStr.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }

        guard !lines.isEmpty else { return nil }

        // Parse status line: "HTTP/1.1 200 OK"
        let statusLine = lines[0]
        var statusCode = 0
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        if statusParts.count >= 2, let code = Int(statusParts[1]) {
            statusCode = code
        }

        // Parse headers
        var httpHeaders: [String: String] = [:]
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                httpHeaders[key.lowercased()] = value
            }
        }

        return (statusCode, httpHeaders, Data(bodyData))
    }
}
