import Foundation
import Testing

@testable import WACZSwift

@Suite("PageSerializer")
struct PageSerializerTests {
    @Test("Serialize and deserialize pages roundtrip")
    func roundtrip() throws {
        let pages = [
            Page(url: "http://example.com/", ts: "2024-01-15T10:30:00Z", title: "Example"),
            Page(url: "http://example.com/about", ts: "2024-01-15T10:30:05Z", title: "About"),
        ]

        let serializer = PageSerializer()
        let data = try serializer.serialize(pages: pages)
        let (header, deserialized) = try serializer.deserialize(from: data)

        #expect(header.format == "json-pages-1.0")
        #expect(deserialized.count == 2)
        #expect(deserialized[0].url == "http://example.com/")
        #expect(deserialized[1].url == "http://example.com/about")
        #expect(deserialized[0].title == "Example")
    }

    @Test("Serialize with text extraction flag")
    func withText() throws {
        let pages = [
            Page(url: "http://example.com/", ts: "2024-01-15T10:30:00Z", title: "Example", text: "Hello world"),
        ]

        let serializer = PageSerializer()
        let data = try serializer.serialize(pages: pages, hasText: true)
        let (header, deserialized) = try serializer.deserialize(from: data)

        #expect(header.hasText == true)
        #expect(deserialized[0].text == "Hello world")
    }

    @Test("Header format is json-pages-1.0")
    func headerFormat() throws {
        let serializer = PageSerializer()
        let data = try serializer.serialize(pages: [])
        let text = String(data: data, encoding: .utf8)!
        let firstLine = text.components(separatedBy: "\n").first!

        #expect(firstLine.contains("json-pages-1.0"))
    }

    @Test("Pages without text don't include text field")
    func noTextField() throws {
        let pages = [
            Page(url: "http://example.com/", ts: "2024-01-15T10:30:00Z"),
        ]

        let serializer = PageSerializer()
        let data = try serializer.serialize(pages: pages)
        let text = String(data: data, encoding: .utf8)!
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Second line is the page entry
        #expect(!lines[1].contains("\"text\""))
    }
}
