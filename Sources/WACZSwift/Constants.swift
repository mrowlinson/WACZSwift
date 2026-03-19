import Foundation

public let waczVersion = "1.1.1"
public let waczSoftware = "WACZSwift 0.1.0"
public let bufferSize = 65536
public let pageIndex = "pages/pages.jsonl"
public let extraPagesIndex = "pages/extraPages.jsonl"
public let pageIndexTemplate = "pages/%@.jsonl"
public let defaultNumLines = 1024

public let htmlMIMETypes: Set<String> = [
    "text/html",
    "application/xhtml",
    "application/xhtml+xml",
]

public enum HashType: String, Sendable, CaseIterable {
    case sha256
    case md5
}
