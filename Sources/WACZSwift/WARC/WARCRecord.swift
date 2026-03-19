import Foundation

public struct WARCRecord: Sendable {
    public let headers: [String: String]
    public let contentBlock: Data

    public var recordType: WARCRecordType? {
        guard let typeStr = headers["WARC-Type"] else { return nil }
        return WARCRecordType(rawValue: typeStr)
    }

    public var targetURI: String? {
        headers["WARC-Target-URI"]
    }

    public var date: Date? {
        guard let dateStr = headers["WARC-Date"] else { return nil }
        return parseWARCDate(dateStr)
    }

    public var contentType: String? {
        headers["Content-Type"]
    }

    public var contentLength: Int? {
        guard let lenStr = headers["Content-Length"] else { return nil }
        return Int(lenStr)
    }

    public var warcPayloadDigest: String? {
        headers["WARC-Payload-Digest"]
    }

    public var warcBlockDigest: String? {
        headers["WARC-Block-Digest"]
    }

    public var warcRefersTo: String? {
        headers["WARC-Refers-To-Target-URI"]
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
