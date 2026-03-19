/// Reason tokens for the WARC-Truncated field (WARC spec section 5.12).
public enum WARCTruncatedReason: String, Sendable {
    case length = "length"
    case time = "time"
    case disconnect = "disconnect"
    case unspecified = "unspecified"
}
