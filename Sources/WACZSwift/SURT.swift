import Foundation

/// Convert a URL string to SURT (Sort-friendly URI Reordering Transform) format.
///
/// Example: "http://www.example.com/path?b=2&a=1" → "com,example,www)/path?a=1&b=2"
public func surtURL(_ urlString: String) -> String? {
    guard let components = URLComponents(string: urlString),
          let host = components.host, !host.isEmpty
    else {
        return nil
    }

    // Reverse and lowercase the hostname, comma-separated
    let reversedHost = host.lowercased()
        .split(separator: ".")
        .reversed()
        .joined(separator: ",")

    // Path (default to /)
    let path = components.path.isEmpty ? "/" : components.path

    // Sort query parameters alphabetically
    var queryString = ""
    if let queryItems = components.queryItems, !queryItems.isEmpty {
        let sorted = queryItems.sorted { a, b in
            if a.name == b.name {
                return (a.value ?? "") < (b.value ?? "")
            }
            return a.name < b.name
        }
        let parts = sorted.map { item in
            if let value = item.value {
                return "\(item.name)=\(value)"
            }
            return item.name
        }
        queryString = "?" + parts.joined(separator: "&")
    }

    return "\(reversedHost))\(path)\(queryString)"
}

// Port number handling: py-wacz's cdxj_indexer strips standard ports (80/443)
// but preserves non-standard ones. URLComponents already strips default ports.
