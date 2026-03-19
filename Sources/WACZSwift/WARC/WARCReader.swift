import Foundation

/// Result of reading a single WARC record from a .warc.gz file.
public struct WARCReadResult: Sendable {
    public let record: WARCRecord
    public let filename: String
    public let offset: Int
    public let length: Int
}

/// Reads WARC records from a .warc.gz file.
///
/// Each record in a .warc.gz is an independent gzip member.
/// Uses C zlib to decompress each member and track compressed offsets.
public final class WARCReader: @unchecked Sendable {
    private let fileURL: URL
    private let filename: String
    private let fileData: Data

    public init(url: URL) throws {
        self.fileURL = url
        self.filename = url.lastPathComponent

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WACZError.fileNotFound(url.path)
        }
        self.fileData = try Data(contentsOf: url)
    }

    /// Read all WARC records from the file.
    public func readRecords() throws -> [WARCReadResult] {
        var results: [WARCReadResult] = []
        var compressedOffset = 0

        while compressedOffset < fileData.count {
            let memberStart = compressedOffset
            let (decompressed, bytesConsumed) = try Gzip.decompressMember(
                from: fileData, offset: compressedOffset
            )
            let memberLength = bytesConsumed

            if let record = try parseWARCRecord(from: decompressed) {
                results.append(WARCReadResult(
                    record: record,
                    filename: filename,
                    offset: memberStart,
                    length: memberLength
                ))
            }

            compressedOffset += bytesConsumed
        }

        return results
    }

    /// Parse a single WARC record from decompressed data.
    /// Works with both text and binary payloads by parsing headers from raw bytes.
    private func parseWARCRecord(from data: Data) throws -> WARCRecord? {
        guard !data.isEmpty else { return nil }

        // Find header/content separator in raw bytes (never decode binary payload as text)
        let crlfcrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])  // \r\n\r\n
        let lflf = Data([0x0A, 0x0A])                     // \n\n

        let separatorEnd: Data.Index
        let headerEnd: Data.Index

        if let range = data.range(of: crlfcrlf) {
            headerEnd = range.lowerBound
            separatorEnd = range.upperBound
        } else if let range = data.range(of: lflf) {
            headerEnd = range.lowerBound
            separatorEnd = range.upperBound
        } else {
            return nil
        }

        // Decode only the header section as text
        let headerData = data[data.startIndex..<headerEnd]
        guard let headerSection = String(data: headerData, encoding: .utf8)
                ?? String(data: headerData, encoding: .ascii) else {
            return nil
        }

        // Parse WARC headers
        let headerLines = headerSection.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }

        guard !headerLines.isEmpty, headerLines[0].hasPrefix("WARC/") else {
            return nil
        }

        var headers: [String: String] = [:]
        for i in 1..<headerLines.count {
            let line = headerLines[i]
            if line.isEmpty { continue }
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Extract content block as raw Data using Content-Length
        let contentLength = headers["Content-Length"].flatMap(Int.init) ?? 0
        let contentBlock: Data

        if contentLength > 0 && separatorEnd + contentLength <= data.endIndex {
            contentBlock = data[separatorEnd..<separatorEnd + contentLength]
        } else if contentLength > 0 {
            // Content-Length exceeds available data — take what we have
            contentBlock = data[separatorEnd..<data.endIndex]
        } else {
            contentBlock = Data()
        }

        return WARCRecord(headers: headers, contentBlock: contentBlock)
    }
}
