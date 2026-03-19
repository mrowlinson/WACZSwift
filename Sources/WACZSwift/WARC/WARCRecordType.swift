import Foundation

public enum WARCRecordType: String, Sendable, CaseIterable {
    case warcinfo
    case response
    case resource
    case request
    case metadata
    case revisit
    case conversion
    case continuation
}
