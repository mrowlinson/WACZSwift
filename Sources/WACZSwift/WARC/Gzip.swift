import CZlibWACZ
import Foundation

/// GZIP compression/decompression via zlib. Each compress() call produces an independent GZIP member,
/// enabling per-record random access as recommended by WARC 1.1 Annex D.
public enum Gzip: Sendable {
    private static let chunkSize = 65536

    /// Compress data into a single gzip member.
    public static func compress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // windowBits = 15 + 16 => GZIP format
        let rc = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION, Z_DEFLATED,
            15 + 16, 8, Z_DEFAULT_STRATEGY,
            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        )
        guard rc == Z_OK else { throw GzipError.initFailed(rc) }
        defer { deflateEnd(&stream) }

        return try data.withUnsafeBytes { ptr -> Data in
            stream.next_in = UnsafeMutablePointer(mutating: ptr.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var out = Data()
            let buf = UnsafeMutablePointer<Bytef>.allocate(capacity: chunkSize)
            defer { buf.deallocate() }
            repeat {
                stream.next_out = buf
                stream.avail_out = uInt(chunkSize)
                let st = deflate(&stream, Z_FINISH)
                guard st != Z_STREAM_ERROR else { throw GzipError.deflate(st) }
                out.append(buf, count: chunkSize - Int(stream.avail_out))
            } while stream.avail_out == 0
            return out
        }
    }

    /// Decompress a single gzip member from the data at the given offset.
    /// Returns (decompressed data, number of compressed bytes consumed).
    /// This preserves per-member offset tracking needed for CDX indexing.
    public static func decompressMember(from data: Data, offset: Int) throws -> (Data, Int) {
        var stream = z_stream()

        // windowBits = 15 + 32 to enable gzip decoding with automatic header detection
        let ret = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard ret == Z_OK else {
            throw GzipError.initFailed(ret)
        }
        defer { inflateEnd(&stream) }

        var output = Data()

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw GzipError.inflate(Z_DATA_ERROR)
            }
            let inputPtr = baseAddress.advanced(by: offset)
            let availableInput = data.count - offset

            stream.next_in = UnsafeMutablePointer<UInt8>(
                mutating: inputPtr.assumingMemoryBound(to: UInt8.self)
            )
            stream.avail_in = UInt32(availableInput)

            let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { outBuffer.deallocate() }

            var status: Int32
            repeat {
                stream.next_out = outBuffer
                stream.avail_out = UInt32(chunkSize)

                status = inflate(&stream, Z_NO_FLUSH)

                if status == Z_STREAM_ERROR || status == Z_DATA_ERROR || status == Z_MEM_ERROR {
                    throw GzipError.inflate(status)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(outBuffer, count: produced)
                }
            } while status != Z_STREAM_END
        }

        let consumed = Int(stream.total_in)
        return (output, consumed)
    }
}

public enum GzipError: Error, Sendable {
    case initFailed(Int32)
    case deflate(Int32)
    case inflate(Int32)
}
