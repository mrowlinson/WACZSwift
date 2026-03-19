import Foundation

/// Writes WARC 1.1 records to a file.
/// When `compress` is true (default), each record is independently GZIP-compressed (per-record gzip per Annex D).
public final class WARCWriter: @unchecked Sendable {

    private let fileHandle: FileHandle
    public let compress: Bool

    public init(path: URL, compress: Bool = true) throws {
        FileManager.default.createFile(atPath: path.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: path)
        self.compress = compress
    }

    public func write(_ record: WARCRecord) throws {
        let headerData = try serializeHeader(record)
        let block = record.contentBlock
        let trailer = Data("\r\n\r\n".utf8)
        if compress {
            let combined = headerData + block + trailer
            let gz = try Gzip.compress(combined)
            fileHandle.write(gz)
        } else {
            fileHandle.write(headerData)
            fileHandle.write(block)
            fileHandle.write(trailer)
        }
    }

    public func close() throws {
        try fileHandle.close()
    }

    // MARK: - Serialization

    /// Headers that are handled explicitly in the serialization order.
    private static let orderedKeys = [
        "WARC-Type", "WARC-Record-ID", "WARC-Date", "Content-Length", "Content-Type",
        "WARC-Target-URI", "WARC-IP-Address", "WARC-Block-Digest", "WARC-Payload-Digest",
        "WARC-Truncated", "WARC-Concurrent-To", "WARC-Refers-To",
        "WARC-Refers-To-Target-URI", "WARC-Refers-To-Date", "WARC-Warcinfo-ID",
        "WARC-Filename", "WARC-Identified-Payload-Type", "WARC-Profile",
        "WARC-Segment-Number", "WARC-Segment-Origin-ID", "WARC-Segment-Total-Length",
    ]

    private func serializeHeader(_ record: WARCRecord) throws -> Data {
        var lines: [String] = ["WARC/1.1"]

        // Ensure Content-Length matches actual block size
        var headers = record.headers
        headers["Content-Length"] = String(record.contentBlock.count)

        let orderedSet = Set(Self.orderedKeys)

        // Write known headers in standard order
        for key in Self.orderedKeys {
            if let value = headers[key] {
                lines.append("\(key): \(value)")
            }
        }

        // Write any remaining custom/unknown headers
        for (key, value) in headers where !orderedSet.contains(key) {
            lines.append("\(key): \(value)")
        }

        // Blank line terminates header; block follows directly after
        lines.append("")
        lines.append("")
        let str = lines.joined(separator: "\r\n")
        guard let data = str.data(using: .utf8) else { throw WARCWriterError.encodingFailed }
        return data
    }
}

public enum WARCWriterError: Error, Sendable {
    case encodingFailed
}
