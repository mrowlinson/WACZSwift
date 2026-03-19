import Foundation
import ZIPFoundation

public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

public struct WACZValidator: Sendable {
    public init() {}

    public func validate(at url: URL, verifyAuth: Bool = false, verifierURL: URL? = nil) throws -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return ValidationResult(isValid: false, errors: ["Failed to open WACZ file as ZIP archive: \(error)"])
        }

        // Collect all entry paths
        let entryPaths = Set(archive.map { $0.path })

        // 1. Check required contents
        let requiredErrors = checkRequiredContents(paths: entryPaths)
        errors.append(contentsOf: requiredErrors)

        // 2. Read and parse datapackage.json
        guard let dpEntry = archive.first(where: { $0.path == "datapackage.json" }) else {
            errors.append("Missing datapackage.json")
            return ValidationResult(isValid: false, errors: errors)
        }

        var dpData = Data()
        _ = try archive.extract(dpEntry) { data in
            dpData.append(data)
        }

        let datapackage: Datapackage
        do {
            datapackage = try JSONDecoder().decode(Datapackage.self, from: dpData)
        } catch {
            errors.append("Invalid datapackage.json: \(error)")
            return ValidationResult(isValid: false, errors: errors)
        }

        // 3. Detect version and hash type
        let version = datapackage.wacz_version
        let hashType = detectHashType(from: datapackage)

        if version.isEmpty {
            warnings.append("No wacz_version found in datapackage.json")
        }

        // 4. Check file paths — every resource path exists in ZIP
        let pathErrors = checkFilePaths(datapackage: datapackage, zipPaths: entryPaths)
        errors.append(contentsOf: pathErrors)

        // 5. Check compression — WARCs and CDX use STORE
        let compressionErrors = checkCompression(archive: archive)
        errors.append(contentsOf: compressionErrors)

        // 6. Check file hashes
        let hashErrors = try checkFileHashes(archive: archive, datapackage: datapackage, hashType: hashType)
        errors.append(contentsOf: hashErrors)

        // 7. Check indexes — regenerate CDX from WARCs, compare hash
        let indexErrors = try checkIndexes(archive: archive, datapackage: datapackage, hashType: hashType)
        errors.append(contentsOf: indexErrors)

        // 8. Check datapackage-digest.json
        let digestErrors = try checkDatapackageDigest(archive: archive, datapackageData: dpData, verifyAuth: verifyAuth, verifierURL: verifierURL)
        errors.append(contentsOf: digestErrors)

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    private func checkRequiredContents(paths: Set<String>) -> [String] {
        var errors: [String] = []

        // Must have datapackage.json
        if !paths.contains("datapackage.json") {
            errors.append("Missing required file: datapackage.json")
        }

        // Must have at least one WARC in archive/
        let hasWARC = paths.contains { $0.hasPrefix("archive/") && ($0.hasSuffix(".warc") || $0.hasSuffix(".warc.gz")) }
        if !hasWARC {
            errors.append("Missing required WARC file in archive/")
        }

        // Must have an index
        let hasIndex = paths.contains("indexes/index.cdx.gz")
            || paths.contains("indexes/index.cdx")
            || paths.contains("indexes/index.idx")
        if !hasIndex {
            errors.append("Missing required index file in indexes/")
        }

        // Must have pages
        if !paths.contains("pages/pages.jsonl") {
            errors.append("Missing required file: pages/pages.jsonl")
        }

        return errors
    }

    private func detectHashType(from datapackage: Datapackage) -> HashType {
        guard let firstResource = datapackage.resources.first else {
            return .sha256
        }
        let prefix = firstResource.hash.components(separatedBy: ":").first ?? "sha256"
        return HashType(rawValue: prefix) ?? .sha256
    }

    private func checkFilePaths(datapackage: Datapackage, zipPaths: Set<String>) -> [String] {
        var errors: [String] = []
        for resource in datapackage.resources {
            if !zipPaths.contains(resource.path) {
                errors.append("Resource path not found in ZIP: \(resource.path)")
            }
        }
        return errors
    }

    private func checkCompression(archive: Archive) -> [String] {
        var errors: [String] = []
        for entry in archive {
            let path = entry.path
            let isWARC = path.hasPrefix("archive/") && (path.hasSuffix(".warc") || path.hasSuffix(".warc.gz"))
            let isCDXGZ = path == "indexes/index.cdx.gz"

            if (isWARC || isCDXGZ) && entry.isCompressed {
                errors.append("File should use STORE compression: \(path)")
            }
        }
        return errors
    }

    private func checkFileHashes(archive: Archive, datapackage: Datapackage, hashType: HashType) throws -> [String] {
        var errors: [String] = []

        for resource in datapackage.resources {
            guard let entry = archive.first(where: { $0.path == resource.path }) else {
                continue // Already caught by checkFilePaths
            }

            var entryData = Data()
            _ = try archive.extract(entry) { data in
                entryData.append(data)
            }

            let computed = hashData(entryData, using: hashType)
            if computed != resource.hash {
                errors.append("Hash mismatch for \(resource.path): expected \(resource.hash), got \(computed)")
            }

            if entryData.count != resource.bytes {
                errors.append("Size mismatch for \(resource.path): expected \(resource.bytes), got \(entryData.count)")
            }
        }

        return errors
    }

    private func checkIndexes(archive: Archive, datapackage: Datapackage, hashType: HashType) throws -> [String] {
        var errors: [String] = []

        // Extract all WARC files to temp directory, re-index, and compare CDX hash
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var warcURLs: [URL] = []
        for entry in archive where entry.path.hasPrefix("archive/") && entry.type == .file {
            let destURL = tempDir.appendingPathComponent((entry.path as NSString).lastPathComponent)
            var warcData = Data()
            _ = try archive.extract(entry) { data in
                warcData.append(data)
            }
            try warcData.write(to: destURL)
            warcURLs.append(destURL)
        }

        guard !warcURLs.isEmpty else { return errors }

        // Sort WARC URLs for deterministic output
        warcURLs.sort { $0.lastPathComponent < $1.lastPathComponent }

        let indexer = CDXIndexer()
        let regeneratedCDX = try indexer.generateCompressedCDX(from: warcURLs)
        let regeneratedHash = hashData(regeneratedCDX, using: hashType)

        // Find the CDX resource in datapackage
        if let cdxResource = datapackage.resources.first(where: { $0.path == "indexes/index.cdx.gz" }) {
            if regeneratedHash != cdxResource.hash {
                errors.append("CDX index hash mismatch: indexes may be outdated or corrupted")
            }
        }

        return errors
    }

    private func checkDatapackageDigest(archive: Archive, datapackageData: Data, verifyAuth: Bool, verifierURL: URL?) throws -> [String] {
        var errors: [String] = []

        guard let digestEntry = archive.first(where: { $0.path == "datapackage-digest.json" }) else {
            errors.append("Missing datapackage-digest.json")
            return errors
        }

        var digestData = Data()
        _ = try archive.extract(digestEntry) { data in
            digestData.append(data)
        }

        let digest: DatapackageDigest
        do {
            digest = try JSONDecoder().decode(DatapackageDigest.self, from: digestData)
        } catch {
            errors.append("Invalid datapackage-digest.json: \(error)")
            return errors
        }

        // Verify hash of datapackage.json (always SHA-256)
        let computedHash = hashData(datapackageData, using: .sha256)
        if computedHash != digest.hash {
            errors.append("Datapackage digest hash mismatch: expected \(digest.hash), got \(computedHash)")
        }

        // Optionally verify signature
        if verifyAuth, let verifierURL = verifierURL, let signedData = digest.signedData {
            let verifyErrors = try verifySignature(signedData: signedData, verifierURL: verifierURL)
            errors.append(contentsOf: verifyErrors)
        }

        return errors
    }

    private func verifySignature(signedData: DatapackageDigest.SignedData, verifierURL: URL) throws -> [String] {
        var request = URLRequest(url: verifierURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(signedData)

        var responseData: Data?
        var responseError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = responseError {
            return ["Signature verification failed: \(error.localizedDescription)"]
        }

        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let valid = json["valid"] as? Bool
        else {
            return ["Invalid response from signature verifier"]
        }

        if !valid {
            return ["Signature verification failed: signature is invalid"]
        }

        return []
    }
}
