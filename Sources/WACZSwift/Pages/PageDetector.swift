import Foundation

public struct PageDetector: Sendable {
    private let textExtractor = TextExtractor()
    private let extractText: Bool

    public init(extractText: Bool = false) {
        self.extractText = extractText
    }

    /// Detect pages from WARC records.
    /// Returns pages detected from HTML response records.
    public func detectPages(from warcURLs: [URL]) throws -> [Page] {
        var pages: [Page] = []
        var seenURLs: Set<String> = []

        for url in warcURLs {
            let reader = try WARCReader(url: url)
            let results = try reader.readRecords()

            for result in results {
                guard let recordType = result.record.recordType,
                      recordType == .response,
                      let targetURI = result.record.targetURI,
                      let date = result.record.date
                else {
                    continue
                }

                guard let http = result.record.parseHTTPContent() else { continue }

                // Only consider successful HTML responses
                guard http.statusCode >= 200, http.statusCode < 400 else { continue }

                let contentType = http.headers["content-type"]?
                    .components(separatedBy: ";").first?
                    .trimmingCharacters(in: .whitespaces).lowercased() ?? ""

                guard htmlMIMETypes.contains(contentType) else { continue }

                // Skip duplicate URLs
                guard !seenURLs.contains(targetURI) else { continue }
                seenURLs.insert(targetURI)

                let ts = isoDate(from: date)
                var title: String?
                var text: String?

                if extractText {
                    let result = textExtractor.extract(from: http.body)
                    title = result.title
                    text = result.text
                } else {
                    // Still try to get the title
                    let result = textExtractor.extract(from: http.body)
                    title = result.title
                }

                pages.append(Page(url: targetURI, ts: ts, title: title, text: text))
            }
        }

        return pages
    }

    /// Split pages into seed pages and secondary pages.
    /// Seed pages are those whose URLs were provided as input seeds.
    public func splitSeeds(pages: [Page], seeds: [String]) -> (seeds: [Page], secondary: [Page]) {
        let seedSet = Set(seeds)
        var seedPages: [Page] = []
        var secondaryPages: [Page] = []

        for page in pages {
            if seedSet.contains(page.url) {
                seedPages.append(page)
            } else {
                secondaryPages.append(page)
            }
        }

        return (seedPages, secondaryPages)
    }
}
