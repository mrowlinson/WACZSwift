import CZlib
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
            let (decompressed, bytesConsumed) = try decompressGzipMember(
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

    /// Decompress a single gzip member from the data at the given offset.
    /// Returns (decompressed data, number of compressed bytes consumed).
    private func decompressGzipMember(from data: Data, offset: Int) throws -> (Data, Int) {
        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        // windowBits = 15 + 32 to enable gzip decoding with automatic header detection
        var ret = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard ret == Z_OK else {
            throw WACZError.zlibError("inflateInit2 failed: \(ret)")
        }
        defer { inflateEnd(&stream) }

        let chunkSize = 65536
        var output = Data()

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw WACZError.zlibError("Failed to access data buffer")
            }
            let inputPtr = baseAddress.advanced(by: offset)
            let availableInput = data.count - offset

            stream.next_in = UnsafeMutablePointer<UInt8>(
                mutating: inputPtr.assumingMemoryBound(to: UInt8.self)
            )
            stream.avail_in = UInt32(availableInput)

            let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { outBuffer.deallocate() }

            repeat {
                stream.next_out = outBuffer
                stream.avail_out = UInt32(chunkSize)

                ret = inflate(&stream, Z_NO_FLUSH)

                if ret == Z_STREAM_ERROR || ret == Z_DATA_ERROR || ret == Z_MEM_ERROR {
                    throw WACZError.zlibError("inflate failed: \(ret)")
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(outBuffer, count: produced)
                }
            } while ret != Z_STREAM_END
        }

        let consumed = Int(stream.total_in)
        return (output, consumed)
    }

    /// Parse a single WARC record from decompressed data.
    private func parseWARCRecord(from data: Data) throws -> WARCRecord? {
        guard !data.isEmpty else { return nil }

        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return nil
        }

        // WARC records have the structure:
        // WARC/1.0\r\n
        // Header: Value\r\n
        // ...\r\n
        // \r\n
        // <content block>
        // \r\n\r\n

        // Find the blank line separating WARC headers from content
        let crlfcrlf = "\r\n\r\n"
        let lflf = "\n\n"

        let separator: String
        let headerEnd: String.Index

        if let range = text.range(of: crlfcrlf) {
            separator = crlfcrlf
            headerEnd = range.lowerBound
        } else if let range = text.range(of: lflf) {
            separator = lflf
            headerEnd = range.lowerBound
        } else {
            return nil
        }

        let headerSection = String(text[text.startIndex..<headerEnd])
        let contentStart = text.index(headerEnd, offsetBy: separator.count)

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

        // Extract content block based on Content-Length
        let contentLength = headers["Content-Length"].flatMap(Int.init) ?? 0
        let contentBlock: Data

        if contentLength > 0 {
            // Get bytes from the content start position
            let headerBytes = headerSection.utf8.count + separator.utf8.count
            if headerBytes + contentLength <= data.count {
                contentBlock = data[data.startIndex.advanced(by: headerBytes)..<data.startIndex.advanced(by: headerBytes + contentLength)]
            } else {
                // Fallback: use what we have after headers
                let remaining = String(text[contentStart...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                contentBlock = Data(remaining.utf8)
            }
        } else {
            contentBlock = Data()
        }

        return WARCRecord(headers: headers, contentBlock: contentBlock)
    }
}
