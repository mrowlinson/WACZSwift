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
            var digest = result.record.payloadDigest ?? ""

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
                digest = result.record.blockDigest ?? ""
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
    /// - Parameter filenamePrefix: Optional prefix to prepend to CDX filename fields
    ///   (e.g. "archive/" so the filename matches the ZIP entry path in a WACZ).
    public func generateCDXJ(from urls: [URL], filenamePrefix: String = "") throws -> String {
        var entries = try indexWARCs(at: urls)
        if !filenamePrefix.isEmpty {
            entries = entries.map { entry in
                CDXEntry(
                    surt: entry.surt,
                    timestamp: entry.timestamp,
                    url: entry.url,
                    mime: entry.mime,
                    status: entry.status,
                    digest: entry.digest,
                    length: entry.length,
                    offset: entry.offset,
                    filename: filenamePrefix + entry.filename
                )
            }
        }
        return entries.map { $0.toCDXJLine() }.joined()
    }

    /// Generate gzip-compressed CDX index data from WARC files.
    /// - Parameter filenamePrefix: Optional prefix to prepend to CDX filename fields
    ///   (e.g. "archive/" so the filename matches the ZIP entry path in a WACZ).
    public func generateCompressedCDX(from urls: [URL], filenamePrefix: String = "") throws -> Data {
        let cdxj = try generateCDXJ(from: urls, filenamePrefix: filenamePrefix)
        let cdxjData = Data(cdxj.utf8)
        return try Gzip.compress(cdxjData)
    }
}
