import Foundation
import Testing

@testable import WACZSwift

@Suite("SURT")
struct SURTTests {
    @Test("Basic URL to SURT")
    func basicSURT() {
        let result = surtURL("http://example.com/")
        #expect(result == "com,example)/")
    }

    @Test("URL with subdomain")
    func subdomainSURT() {
        let result = surtURL("http://www.example.com/path")
        #expect(result == "com,example,www)/path")
    }

    @Test("URL with query params sorted")
    func queryParamsSorted() {
        let result = surtURL("http://example.com/page?b=2&a=1")
        #expect(result == "com,example)/page?a=1&b=2")
    }

    @Test("HTTPS URL")
    func httpsSURT() {
        let result = surtURL("https://archive.org/web/")
        #expect(result == "org,archive)/web/")
    }

    @Test("Invalid URL returns nil")
    func invalidURL() {
        let result = surtURL("not a url")
        #expect(result == nil)
    }

    @Test("URL with deep path")
    func deepPath() {
        let result = surtURL("http://example.com/a/b/c/d")
        #expect(result == "com,example)/a/b/c/d")
    }
}
