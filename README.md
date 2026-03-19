# WACZSwift

A Swift port of [py-wacz](https://github.com/webrecorder/py-wacz) — the Python library for creating and validating [WACZ](https://specs.webrecorder.net/wacz/1.1.1/) (Web Archive Collection Zipped) files.

WACZ is a standardized ZIP-based format for packaging WARC web archives with CDX indexes, page metadata, and cryptographic integrity verification.

## Features

- **Create** WACZ files from `.warc.gz` archives with full spec compliance (WACZ 1.1.1)
- **Validate** WACZ files — structure, hashes, indexes, and optional signature verification
- **Read** WARC records with per-member offset tracking for CDX indexing
- **Write** WARC records to `.warc` or `.warc.gz` files with per-record gzip compression
- **CDX indexing** — generates sorted CDXJ indexes with gzip compression
- **Page detection** — automatic HTML page identification with text extraction via SwiftSoup
- **Cryptographic hashing** — SHA-256 (default) and MD5 via CryptoKit
- **HTTP signing** — optional datapackage signing via external signing service
- Both a **library** (`WACZSwift`) and a **CLI** (`wacz`) target

## Requirements

- Swift 6.0+
- macOS 13+ / iOS 16+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mrowlinson/WACZSwift.git", from: "0.1.0"),
]
```

Then add `"WACZSwift"` as a dependency of your target.

### CLI

```bash
git clone https://github.com/mrowlinson/WACZSwift.git
cd WACZSwift
swift build -c release
# Binary at .build/release/wacz
```

## Usage

### CLI

```bash
# Create a WACZ from WARC files
wacz create recording.warc.gz -o archive.wacz --title "My Archive"

# Create with text extraction and metadata
wacz create site.warc.gz -o site.wacz -t --title "Site Backup" --desc "Full crawl" --url "https://example.com"

# Create with MD5 hashing
wacz create recording.warc.gz -o archive.wacz --hash-type md5

# Validate a WACZ file
wacz validate -f archive.wacz

# Validate with signature verification
wacz validate -f archive.wacz --verify-auth --verifier-url https://auth.example.com/verify
```

### Library

```swift
import WACZSwift

// Create a WACZ
let options = WACZCreatorOptions(
    inputs: [URL(fileURLWithPath: "recording.warc.gz")],
    output: URL(fileURLWithPath: "output.wacz"),
    title: "My Archive",
    description: "A web archive",
    extractText: true
)
let creator = WACZCreator()
try creator.create(options: options)

// Validate a WACZ
let validator = WACZValidator()
let result = try validator.validate(at: URL(fileURLWithPath: "output.wacz"))
if result.isValid {
    print("Valid!")
} else {
    print("Errors: \(result.errors)")
}

// Read WARC records
let reader = try WARCReader(url: URL(fileURLWithPath: "recording.warc.gz"))
let records = try reader.readRecords()
for r in records {
    print("\(r.record.recordType!) \(r.record.targetURI ?? "")")
}

// Generate CDX index
let indexer = CDXIndexer()
let entries = try indexer.indexWARC(at: URL(fileURLWithPath: "recording.warc.gz"))
for entry in entries {
    print(entry.toCDXJLine())
}

// Write WARC records
let writer = try WARCWriter(path: URL(fileURLWithPath: "output.warc.gz"), compress: true)
let record = WARCRecord(
    headers: [
        "WARC-Type": "resource",
        "WARC-Record-ID": WARCRecord.generateRecordID(),
        "WARC-Date": WARCDate.string(from: Date()),
        "WARC-Target-URI": "http://example.com/data.txt",
        "Content-Type": "text/plain",
    ],
    contentBlock: Data("Hello, world!".utf8)
)
try writer.write(record)
try writer.close()
```

## Architecture

```
Sources/WACZSwift/
  Constants.swift               WACZ version, hash types, buffer sizes
  Hashing.swift                 CryptoKit-based SHA-256/MD5 hashing
  Timestamps.swift              CDXJ/ISO 8601 date handling
  SURT.swift                    URL to SURT conversion for CDX keys
  WARC/
    Gzip.swift                  Gzip compression/decompression via C zlib
    WARCDate.swift              WARC-Date parsing/formatting (ISO 8601 with fractional seconds)
    WARCRecordType.swift        Record type enum (CaseIterable)
    WARCTruncatedReason.swift   WARC-Truncated reason tokens
    WARCRecord.swift            Record struct with typed accessors and HTTP content parsing
    WARCReader.swift            Per-member gzip decompression with offset tracking
    WARCWriter.swift            Write WARC records to .warc/.warc.gz files
  CDX/
    CDXEntry.swift              CDXJ line struct
    CDXIndexer.swift            WARC to sorted, gzip-compressed CDX
  Pages/
    Page.swift                  Page + header Codable structs
    TextExtractor.swift         SwiftSoup HTML to plain text
    PageDetector.swift          HTML response detection from WARCs
    PageSerializer.swift        JSONL serialization
  Datapackage/
    Datapackage.swift           datapackage.json struct
    DatapackageResource.swift   Resource entry
    DatapackageDigest.swift     Digest + signed data
  WACZCreator.swift             WACZ creation orchestration
  WACZValidator.swift           Validation checks
Sources/wacz/
  WACZCommand.swift             CLI entry point
  CreateCommand.swift           create subcommand
  ValidateCommand.swift         validate subcommand
```

## WACZ File Format

A `.wacz` file is a ZIP archive containing:

```
archive/*.warc.gz           WARC files (ZIP STORE)
indexes/index.cdx.gz        Sorted CDXJ index (ZIP STORE, pre-gzipped)
pages/pages.jsonl           Detected pages (ZIP DEFLATE)
datapackage.json            Resource manifest with hashes (ZIP DEFLATE)
datapackage-digest.json     SHA-256 digest of datapackage (ZIP DEFLATE)
```

## Differences from py-wacz

- **Text extraction**: Uses SwiftSoup instead of boilerpy3. Strips non-content elements (script, style, nav, header, footer) and extracts body text rather than full article extraction.
- **Datapackage validation**: Performs structural validation directly rather than using the frictionless library for full schema validation.
- **Concurrency**: All types are `Sendable`-conformant structs (Swift 6 strict concurrency).

## Dependencies

| Package | Purpose |
|---------|---------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | ZIP read/write |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML parsing for text extraction |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI |
| CryptoKit (Apple) | SHA-256 / MD5 |
| zlib (Darwin) | Gzip compression/decompression |

## License

MIT

## Acknowledgments

This project is a Swift port of [py-wacz](https://github.com/webrecorder/py-wacz) by [Webrecorder](https://webrecorder.net/). The WACZ format is specified at [specs.webrecorder.net/wacz](https://specs.webrecorder.net/wacz/1.1.1/).
