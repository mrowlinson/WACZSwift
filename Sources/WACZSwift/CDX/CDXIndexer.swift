import CZlib
import Foundation

public struct CDXIndexer: Sendable {
    public init() {}

    /// Index a WARC file and return CDX entries sorted by SURT + timestamp.
    public func indexWARC(at url: URL) throws -> [CDXEntry] {
        let reader = try WARCReader(url: url)
        let results = try reader.readRecords()
        var entries: [CDXEntry] = []

        for result in results {
            guard let recordType = result.record.recordType,
                  recordType == .response || recordType == .resource || recordType == .revisit
            else {
                continue
            }

            guard let targetURI = result.record.targetURI,
                  let date = result.record.date,
                  let surt = surtURL(targetURI)
            else {
                continue
            }

            let timestamp = cdxjTimestamp(from: date)

            var mime = ""
            var status = ""
            var digest = result.record.warcPayloadDigest ?? ""

            if recordType == .response, let http = result.record.parseHTTPContent() {
                status = String(http.statusCode)
                mime = http.headers["content-type"]?.components(separatedBy: ";").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
            } else if recordType == .resource {
                mime = result.record.contentType?.components(separatedBy: ";").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                status = "200"
            } else if recordType == .revisit {
                mime = "warc/revisit"
                status = ""
            }

            if digest.isEmpty {
                digest = result.record.warcBlockDigest ?? ""
            }

            entries.append(CDXEntry(
                surt: surt,
                timestamp: timestamp,
                url: targetURI,
                mime: mime,
                status: status,
                digest: digest,
                length: String(result.length),
                offset: String(result.offset),
                filename: result.filename
            ))
        }

        entries.sort()
        return entries
    }

    /// Index multiple WARC files and return all CDX entries sorted.
    public func indexWARCs(at urls: [URL]) throws -> [CDXEntry] {
        var allEntries: [CDXEntry] = []
        for url in urls {
            let entries = try indexWARC(at: url)
            allEntries.append(contentsOf: entries)
        }
        allEntries.sort()
        return allEntries
    }

    /// Generate sorted CDXJ lines from WARC files.
    public func generateCDXJ(from urls: [URL]) throws -> String {
        let entries = try indexWARCs(at: urls)
        return entries.map { $0.toCDXJLine() }.joined()
    }

    /// Generate gzip-compressed CDX index data from WARC files.
    public func generateCompressedCDX(from urls: [URL]) throws -> Data {
        let cdxj = try generateCDXJ(from: urls)
        let cdxjData = Data(cdxj.utf8)
        return try gzipCompress(cdxjData)
    }
}

/// Gzip compress data using zlib.
public func gzipCompress(_ data: Data) throws -> Data {
    var stream = z_stream()
    stream.zalloc = nil
    stream.zfree = nil
    stream.opaque = nil

    // windowBits = 15 + 16 for gzip encoding
    var ret = deflateInit2_(
        &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
        15 + 16, 8, Z_DEFAULT_STRATEGY,
        ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
    )
    guard ret == Z_OK else {
        throw WACZError.zlibError("deflateInit2 failed: \(ret)")
    }
    defer { deflateEnd(&stream) }

    var output = Data()
    let chunkSize = 65536
    let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
    defer { outBuffer.deallocate() }

    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            throw WACZError.zlibError("Failed to access data buffer")
        }

        stream.next_in = UnsafeMutablePointer<UInt8>(
            mutating: baseAddress.assumingMemoryBound(to: UInt8.self)
        )
        stream.avail_in = UInt32(data.count)

        repeat {
            stream.next_out = outBuffer
            stream.avail_out = UInt32(chunkSize)

            ret = deflate(&stream, Z_FINISH)
            if ret == Z_STREAM_ERROR {
                throw WACZError.zlibError("deflate failed: \(ret)")
            }

            let produced = chunkSize - Int(stream.avail_out)
            if produced > 0 {
                output.append(outBuffer, count: produced)
            }
        } while ret != Z_STREAM_END
    }

    return output
}
