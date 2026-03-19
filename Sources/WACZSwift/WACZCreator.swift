import CryptoKit
import Foundation
import ZIPFoundation

public struct WACZCreatorOptions: Sendable {
    public var inputs: [URL]
    public var output: URL
    public var hashType: HashType
    public var title: String?
    public var description: String?
    public var mainPageURL: String?
    public var mainPageDate: String?
    public var customPages: URL?
    public var copyPages: Bool
    public var extraPages: URL?
    public var logDirectory: URL?
    public var extractText: Bool
    public var splitSeeds: [String]?
    public var signingURL: URL?
    public var signingToken: String?

    public init(
        inputs: [URL],
        output: URL,
        hashType: HashType = .sha256,
        title: String? = nil,
        description: String? = nil,
        mainPageURL: String? = nil,
        mainPageDate: String? = nil,
        customPages: URL? = nil,
        copyPages: Bool = false,
        extraPages: URL? = nil,
        logDirectory: URL? = nil,
        extractText: Bool = false,
        splitSeeds: [String]? = nil,
        signingURL: URL? = nil,
        signingToken: String? = nil
    ) {
        self.inputs = inputs
        self.output = output
        self.hashType = hashType
        self.title = title
        self.description = description
        self.mainPageURL = mainPageURL
        self.mainPageDate = mainPageDate
        self.customPages = customPages
        self.copyPages = copyPages
        self.extraPages = extraPages
        self.logDirectory = logDirectory
        self.extractText = extractText
        self.splitSeeds = splitSeeds
        self.signingURL = signingURL
        self.signingToken = signingToken
    }
}

public struct WACZCreator: Sendable {
    public init() {}

    public func create(options: WACZCreatorOptions) throws {
        let fm = FileManager.default

        // Remove existing output file
        if fm.fileExists(atPath: options.output.path) {
            try fm.removeItem(at: options.output)
        }

        let archive = try Archive(url: options.output, accessMode: .create)

        // 1. Index all WARCs → CDX entries + detect pages
        let indexer = CDXIndexer()
        let cdxData = try indexer.generateCompressedCDX(from: options.inputs)

        let detector = PageDetector(extractText: options.extractText)
        var pages: [Page]

        if let customPagesURL = options.customPages {
            // Load custom pages
            let customData = try Data(contentsOf: customPagesURL)
            let serializer = PageSerializer()
            let (_, customPages) = try serializer.deserialize(from: customData)
            pages = customPages
        } else {
            pages = try detector.detectPages(from: options.inputs)
        }

        // 2. Write CDX index (STORE — already gzipped)
        try archive.addEntry(
            with: "indexes/index.cdx.gz",
            type: .file,
            uncompressedSize: Int64(cdxData.count),
            compressionMethod: .none,
            provider: { position, size in
                cdxData[Int(position)..<Int(position) + size]
            }
        )

        // 3. Copy WARC files to archive/ (STORE)
        for input in options.inputs {
            let warcData = try Data(contentsOf: input)
            let entryPath = "archive/\(input.lastPathComponent)"
            try archive.addEntry(
                with: entryPath,
                type: .file,
                uncompressedSize: Int64(warcData.count),
                compressionMethod: .none,
                provider: { position, size in
                    warcData[Int(position)..<Int(position) + size]
                }
            )
        }

        // 4. Handle page splitting if seeds provided
        var extraPagesList: [Page]?
        if let seeds = options.splitSeeds, !seeds.isEmpty {
            let (seedPages, secondaryPages) = detector.splitSeeds(pages: pages, seeds: seeds)
            pages = seedPages
            if !secondaryPages.isEmpty {
                extraPagesList = secondaryPages
            }
        }

        // 5. Write pages JSONL (DEFLATE)
        let serializer = PageSerializer()
        let pagesData = try serializer.serialize(pages: pages, hasText: options.extractText)
        try addDeflateEntry(to: archive, path: pageIndex, data: pagesData)

        // 5b. Write extra pages if present
        if let extraPages = extraPagesList {
            let extraData = try serializer.serialize(pages: extraPages, hasText: options.extractText)
            try addDeflateEntry(to: archive, path: extraPagesIndex, data: extraData)
        }

        // 5c. Copy extra pages file if provided
        if let extraPagesURL = options.extraPages {
            let extraData = try Data(contentsOf: extraPagesURL)
            try addDeflateEntry(to: archive, path: extraPagesIndex, data: extraData)
        }

        // 6. Write log files if log directory specified
        if let logDir = options.logDirectory {
            let logFiles = try fm.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil)
            for logFile in logFiles {
                let logData = try Data(contentsOf: logFile)
                let entryPath = "logs/\(logFile.lastPathComponent)"
                try archive.addEntry(
                    with: entryPath,
                    type: .file,
                    uncompressedSize: Int64(logData.count),
                    compressionMethod: .none,
                    provider: { position, size in
                        logData[Int(position)..<Int(position) + size]
                    }
                )
            }
        }

        // 7. Generate datapackage.json — hash every ZIP entry
        var datapackage = Datapackage()
        datapackage.title = options.title
        datapackage.description = options.description
        datapackage.mainPageURL = options.mainPageURL
        datapackage.mainPageDate = options.mainPageDate

        // We need to re-read the archive to hash each entry
        // Close and re-open to ensure all entries are flushed
        let readArchive = try Archive(url: options.output, accessMode: .read)

        for entry in readArchive {
            guard entry.type == .file else { continue }
            var entryData = Data()
            _ = try readArchive.extract(entry) { data in
                entryData.append(data)
            }

            let hash = hashData(entryData, using: options.hashType)
            let name = (entry.path as NSString).lastPathComponent.lowercased()

            datapackage.resources.append(DatapackageResource(
                name: name,
                path: entry.path,
                hash: hash,
                bytes: entryData.count
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let datapackageData = try encoder.encode(datapackage)

        // Append datapackage.json to the archive
        let writeArchive = try Archive(url: options.output, accessMode: .update)
        try addDeflateEntry(to: writeArchive, path: "datapackage.json", data: datapackageData)

        // 8. Generate datapackage-digest.json
        // Always use SHA-256 for the digest hash regardless of hashType
        let digestHash = hashData(datapackageData, using: .sha256)
        var digest = DatapackageDigest(path: "datapackage.json", hash: digestHash)

        // Handle signing if configured
        if let signingURL = options.signingURL {
            let signedData = try signDatapackage(
                hash: digestHash,
                created: datapackage.created,
                signingURL: signingURL,
                signingToken: options.signingToken
            )
            digest.signedData = signedData
        }

        let digestData = try encoder.encode(digest)
        try addDeflateEntry(to: writeArchive, path: "datapackage-digest.json", data: digestData)
    }

    private func addDeflateEntry(to archive: Archive, path: String, data: Data) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate,
            provider: { position, size in
                data[Int(position)..<Int(position) + size]
            }
        )
    }

    private func signDatapackage(
        hash: String,
        created: String,
        signingURL: URL,
        signingToken: String?
    ) throws -> DatapackageDigest.SignedData {
        var request = URLRequest(url: signingURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = signingToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: String] = ["hash": hash, "created": created]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var responseData: Data?
        var responseError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = responseError {
            throw WACZError.signingFailed(error.localizedDescription)
        }

        guard let data = responseData else {
            throw WACZError.signingFailed("No response from signing server")
        }

        let signedData = try JSONDecoder().decode(DatapackageDigest.SignedData.self, from: data)

        // Verify the response matches what we sent
        guard signedData.hash == hash, signedData.created == created else {
            throw WACZError.signingFailed("Signing response hash/created mismatch")
        }

        return signedData
    }
}
