import Foundation
import zlib

public enum ZipArchiveError: Error, Sendable, Equatable, LocalizedError {
    case invalidArchive
    case unsupportedCompression(UInt16)
    case unsafePath(String)
    case entryLimitExceeded
    case sizeLimitExceeded
    case crcMismatch(String)
    case compressionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "Invalid or corrupted ZIP archive."
        case .unsupportedCompression(let method):
            return "Unsupported ZIP compression method: \(method)."
        case .unsafePath(let path):
            return "Blocked unsafe archive path: \(path)."
        case .entryLimitExceeded:
            return "Archive exceeds maximum entry count limit."
        case .sizeLimitExceeded:
            return "Archive exceeds maximum size safety limit."
        case .crcMismatch(let name):
            return "CRC-32 checksum mismatch for entry \(name)."
        case .compressionFailed:
            return "ZIP compression/decompression failed."
        }
    }
}

public struct ZipArchive: Sendable {
    public static let maxEntryCount = 10_000
    public static let maxSingleFileBytes = 256 * 1024 * 1024
    public static let maxTotalUncompressedBytes = 1_536 * 1024 * 1024

    public static func looksLikeZip(_ data: Data) -> Bool {
        data.count >= 4 && data[0] == 0x50 && data[1] == 0x4B && (data[2] == 0x03 || data[2] == 0x05)
    }

    public static func encode(files: [String: Data], compressText: Bool = true) throws -> Data {
        let sortedNames = files.keys.sorted()
        if sortedNames.count > maxEntryCount {
            throw ZipArchiveError.entryLimitExceeded
        }

        var archive = Data()
        var centralDirectory = Data()

        for name in sortedNames {
            guard let rawData = files[name], isSafeRelativePath(name) else {
                throw ZipArchiveError.unsafePath(name)
            }
            let nameData = Data(name.utf8)
            let crc = crc32Checksum(rawData)
            let shouldDeflate = compressText && rawData.count > 64 && !isAlreadyCompressedExtension(name)
            let payload: Data
            let method: UInt16
            if shouldDeflate, let deflated = rawDeflate(rawData), deflated.count < rawData.count {
                payload = deflated
                method = 8
            } else {
                payload = rawData
                method = 0
            }

            let localHeaderOffset = UInt32(archive.count)
            let utf8Flag: UInt16 = 0x0800
            let uncompressedSize = UInt32(rawData.count)
            let compressedSize = UInt32(payload.count)

            // Local file header (30 bytes + name)
            appendUInt32(&archive, 0x04034B50)
            appendUInt16(&archive, 20)
            appendUInt16(&archive, utf8Flag)
            appendUInt16(&archive, method)
            appendUInt16(&archive, 0) // mod time
            appendUInt16(&archive, 0x5421) // mod date
            appendUInt32(&archive, crc)
            appendUInt32(&archive, compressedSize)
            appendUInt32(&archive, uncompressedSize)
            appendUInt16(&archive, UInt16(nameData.count))
            appendUInt16(&archive, 0)
            archive.append(nameData)
            archive.append(payload)

            // Central directory header (46 bytes + name)
            appendUInt32(&centralDirectory, 0x02014B50)
            appendUInt16(&centralDirectory, 20)
            appendUInt16(&centralDirectory, 20)
            appendUInt16(&centralDirectory, utf8Flag)
            appendUInt16(&centralDirectory, method)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0x5421)
            appendUInt32(&centralDirectory, crc)
            appendUInt32(&centralDirectory, compressedSize)
            appendUInt32(&centralDirectory, uncompressedSize)
            appendUInt16(&centralDirectory, UInt16(nameData.count))
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt32(&centralDirectory, 0)
            appendUInt32(&centralDirectory, localHeaderOffset)
            centralDirectory.append(nameData)
        }

        let cdOffset = UInt32(archive.count)
        let cdSize = UInt32(centralDirectory.count)
        let count = UInt16(sortedNames.count)
        archive.append(centralDirectory)

        // End of central directory record (22 bytes)
        appendUInt32(&archive, 0x06054B50)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, count)
        appendUInt16(&archive, count)
        appendUInt32(&archive, cdSize)
        appendUInt32(&archive, cdOffset)
        appendUInt16(&archive, 0)

        return archive
    }

    public static func decode(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22 else {
            throw ZipArchiveError.invalidArchive
        }
        guard let eocdIndex = findEOCDOffset(in: data) else {
            throw ZipArchiveError.invalidArchive
        }

        let totalEntries = Int(readUInt16(data, at: eocdIndex + 10))
        if totalEntries > maxEntryCount {
            throw ZipArchiveError.entryLimitExceeded
        }
        let cdSize = Int(readUInt32(data, at: eocdIndex + 12))
        let cdOffset = Int(readUInt32(data, at: eocdIndex + 16))
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= eocdIndex else {
            throw ZipArchiveError.invalidArchive
        }

        var result: [String: Data] = [:]
        var cursor = cdOffset
        var totalUncompressed = 0

        for _ in 0..<totalEntries {
            guard cursor + 46 <= cdOffset + cdSize,
                  readUInt32(data, at: cursor) == 0x02014B50 else {
                throw ZipArchiveError.invalidArchive
            }
            let method = readUInt16(data, at: cursor + 10)
            let expectedCrc = readUInt32(data, at: cursor + 16)
            let compressedSize = Int(readUInt32(data, at: cursor + 20))
            let uncompressedSize = Int(readUInt32(data, at: cursor + 24))
            let nameLength = Int(readUInt16(data, at: cursor + 28))
            let extraLength = Int(readUInt16(data, at: cursor + 30))
            let commentLength = Int(readUInt16(data, at: cursor + 32))
            let localHeaderOffset = Int(readUInt32(data, at: cursor + 42))

            let headerEnd = cursor + 46 + nameLength + extraLength + commentLength
            guard headerEnd <= cdOffset + cdSize else {
                throw ZipArchiveError.invalidArchive
            }
            let nameSlice = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            guard let name = String(data: nameSlice, encoding: .utf8) else {
                throw ZipArchiveError.invalidArchive
            }
            cursor = headerEnd

            // Skip directory entries safely
            if name.hasSuffix("/") {
                continue
            }
            guard isSafeRelativePath(name) else {
                throw ZipArchiveError.unsafePath(name)
            }
            if uncompressedSize > maxSingleFileBytes {
                throw ZipArchiveError.sizeLimitExceeded
            }
            totalUncompressed += uncompressedSize
            if totalUncompressed > maxTotalUncompressedBytes {
                throw ZipArchiveError.sizeLimitExceeded
            }

            // Read local header
            guard localHeaderOffset >= 0,
                  localHeaderOffset + 30 <= cdOffset,
                  readUInt32(data, at: localHeaderOffset) == 0x04034B50 else {
                throw ZipArchiveError.invalidArchive
            }
            let localNameLen = Int(readUInt16(data, at: localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16(data, at: localHeaderOffset + 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            let payloadEnd = payloadStart + compressedSize
            guard payloadStart >= 0, payloadEnd <= cdOffset else {
                throw ZipArchiveError.invalidArchive
            }

            let compressedSlice = data.subdata(in: payloadStart..<payloadEnd)
            let uncompressed: Data
            switch method {
            case 0:
                uncompressed = compressedSlice
            case 8:
                uncompressed = try rawInflate(compressedSlice, expectedSize: uncompressedSize)
            default:
                throw ZipArchiveError.unsupportedCompression(method)
            }

            guard uncompressed.count == uncompressedSize else {
                throw ZipArchiveError.invalidArchive
            }
            let actualCrc = crc32Checksum(uncompressed)
            guard actualCrc == expectedCrc else {
                throw ZipArchiveError.crcMismatch(name)
            }
            result[name] = uncompressed
        }

        return result
    }

    public static func isSafeRelativePath(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.hasPrefix("\\") || path.contains("\\") {
            return false
        }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        for seg in segments {
            if seg.isEmpty || seg == "." || seg == ".." {
                return false
            }
        }
        return true
    }

    private static func isAlreadyCompressedExtension(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png")
            || lower.hasSuffix(".heic") || lower.hasSuffix(".webp") || lower.hasSuffix(".mp4")
            || lower.hasSuffix(".mov") || lower.hasSuffix(".zip")
    }

    private static func crc32Checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { rawBuffer -> UInt32 in
            guard let ptr = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return 0
            }
            let result = zlib.crc32(0, ptr, uInt(data.count))
            return UInt32(truncatingIfNeeded: result)
        }
    }

    private static func rawDeflate(_ data: Data) -> Data? {
        if data.isEmpty { return Data() }
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { return nil }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 32_768
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        let success = data.withUnsafeBytes { rawBuffer -> Bool in
            guard let inputPtr = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return false
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPtr)
            stream.avail_in = uInt(data.count)

            repeat {
                let status: Int32 = buffer.withUnsafeMutableBytes { outRaw in
                    let outPtr = outRaw.bindMemory(to: Bytef.self).baseAddress!
                    stream.next_out = outPtr
                    stream.avail_out = uInt(chunkSize)
                    return deflate(&stream, Z_FINISH)
                }
                if status == Z_STREAM_ERROR {
                    return false
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
                if status == Z_STREAM_END {
                    return true
                }
            } while stream.avail_out == 0
            return true
        }
        return success ? output : nil
    }

    private static func rawInflate(_ data: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw ZipArchiveError.compressionFailed
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(min(expectedSize, 1_048_576))
        let chunkSize = 65_536
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        var streamError = false
        var totalDecoded = 0

        data.withUnsafeBytes { rawBuffer in
            guard let inputPtr = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                streamError = true
                return
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPtr)
            stream.avail_in = uInt(data.count)

            while true {
                let status: Int32 = buffer.withUnsafeMutableBytes { outRaw in
                    let outPtr = outRaw.bindMemory(to: Bytef.self).baseAddress!
                    stream.next_out = outPtr
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    totalDecoded += produced
                    if totalDecoded > maxSingleFileBytes || totalDecoded > expectedSize {
                        streamError = true
                        return
                    }
                    output.append(buffer, count: produced)
                }
                if status == Z_STREAM_END {
                    break
                }
                if status != Z_OK {
                    streamError = true
                    return
                }
                if stream.avail_in == 0 && stream.avail_out > 0 {
                    break
                }
            }
        }
        if streamError {
            throw ZipArchiveError.compressionFailed
        }
        return output
    }

    private static func findEOCDOffset(in data: Data) -> Int? {
        let minOffset = max(0, data.count - (22 + 65_535))
        var i = data.count - 22
        while i >= minOffset {
            if data[i] == 0x50 && data[i + 1] == 0x4B && data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
