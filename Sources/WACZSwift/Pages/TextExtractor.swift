import Foundation
import SwiftSoup

public struct TextExtractor: Sendable {
    public init() {}

    /// Extract plain text content and title from HTML data.
    public func extract(from htmlData: Data) -> (title: String?, text: String?) {
        guard let html = String(data: htmlData, encoding: .utf8)
                ?? String(data: htmlData, encoding: .ascii)
        else {
            return (nil, nil)
        }

        return extract(from: html)
    }

    /// Extract plain text content and title from HTML string.
    public func extract(from html: String) -> (title: String?, text: String?) {
        do {
            let doc = try SwiftSoup.parse(html)

            // Extract title
            let title = try doc.title().isEmpty ? nil : doc.title()

            // Remove non-content elements
            let removeSelectors = ["script", "style", "nav", "header", "footer", "aside", "noscript"]
            for selector in removeSelectors {
                try doc.select(selector).remove()
            }

            // Extract body text
            guard let body = doc.body() else {
                return (title, nil)
            }

            let text = try body.text()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            return (title, trimmed.isEmpty ? nil : trimmed)
        } catch {
            return (nil, nil)
        }
    }
}
