import Foundation

public struct PageListHeader: Codable, Sendable {
    public var format: String = "json-pages-1.0"
    public var id: String = "pages"
    public var title: String = "Pages"
    public var hasText: Bool?

    public init(hasText: Bool = false) {
        if hasText {
            self.hasText = true
        }
    }
}

public struct Page: Codable, Sendable {
    public var url: String
    public var ts: String
    public var title: String?
    public var id: String
    public var text: String?

    public init(url: String, ts: String, title: String? = nil, id: String? = nil, text: String? = nil) {
        self.url = url
        self.ts = ts
        self.title = title
        self.id = id ?? UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(22).description
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case url, ts, title, id, text
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(ts, forKey: .ts)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(text, forKey: .text)
    }
}
