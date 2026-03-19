import Foundation

public struct PageSerializer: Sendable {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder = JSONDecoder()

    public init() {}

    /// Serialize pages to JSONL format (header line + page lines).
    public func serialize(pages: [Page], hasText: Bool = false) throws -> Data {
        let header = PageListHeader(hasText: hasText)
        let headerData = try Self.encoder.encode(header)

        var lines: [Data] = [headerData]
        for page in pages {
            let pageData = try Self.encoder.encode(page)
            lines.append(pageData)
        }

        let joined = lines.map { String(data: $0, encoding: .utf8)! }.joined(separator: "\n")
        return Data((joined + "\n").utf8)
    }

    /// Deserialize pages from JSONL data.
    public func deserialize(from data: Data) throws -> (header: PageListHeader, pages: [Page]) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw WACZError.invalidWACZ("Invalid page list encoding")
        }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            throw WACZError.invalidWACZ("Empty page list")
        }

        let headerData = Data(lines[0].utf8)
        let header = try Self.decoder.decode(PageListHeader.self, from: headerData)

        var pages: [Page] = []
        for i in 1..<lines.count {
            let pageData = Data(lines[i].utf8)
            let page = try Self.decoder.decode(Page.self, from: pageData)
            pages.append(page)
        }

        return (header, pages)
    }
}
