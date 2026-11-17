import Foundation

public enum MediaAttachmentType: String, Codable, Sendable, CaseIterable {
    case image
    case video
    case motionPhoto
    case sketch

    /// Portable v2 schema only accepts "image", "video", or "motionPhoto".
    public var portableTypeString: String {
        switch self {
        case .image, .sketch:
            return "image"
        case .video:
            return "video"
        case .motionPhoto:
            return "motionPhoto"
        }
    }
}

public struct MediaAttachment: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let type: MediaAttachmentType
    public let mediaId: String
    public let motionVideoMediaId: String?
    public let legacySource: String?
    public let mimeType: String
    public let byteSize: Int64

    public var isImage: Bool {
        type == .image || type == .motionPhoto || type == .sketch
    }

    public var isVideo: Bool {
        type == .video || (type == .motionPhoto && !(motionVideoMediaId ?? "").isEmpty)
    }

    public var sourcePath: String {
        legacySource ?? mediaId
    }

    public var videoSourcePath: String? {
        switch type {
        case .video:
            return sourcePath
        case .motionPhoto:
            return motionVideoMediaId
        case .image, .sketch:
            return nil
        }
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        type: MediaAttachmentType,
        mediaId: String,
        motionVideoMediaId: String? = nil,
        legacySource: String? = nil,
        mimeType: String? = nil,
        byteSize: Int64 = 0
    ) {
        self.id = id
        self.type = type
        self.mediaId = mediaId
        self.motionVideoMediaId = motionVideoMediaId
        self.legacySource = legacySource
        self.mimeType = mimeType ?? MediaAttachment.defaultMimeType(for: type, path: mediaId)
        self.byteSize = byteSize
    }

    public static func defaultMimeType(for type: MediaAttachmentType, path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".heic") { return "image/heic" }
        if lower.hasSuffix(".mov") { return "video/quicktime" }
        if lower.hasSuffix(".mp4") { return "video/mp4" }
        switch type {
        case .video:
            return "video/mp4"
        case .sketch:
            return "image/png"
        case .image, .motionPhoto:
            return "image/jpeg"
        }
    }

    public static func fileExtension(for mimeType: String, fallbackPath: String = "") -> String {
        switch mimeType.lowercased() {
        case "image/png": return ".png"
        case "image/webp": return ".webp"
        case "image/gif": return ".gif"
        case "image/heic": return ".heic"
        case "image/jpeg", "image/jpg": return ".jpg"
        case "video/quicktime": return ".mov"
        case "video/mp4": return ".mp4"
        default:
            let clean = fallbackPath.split(separator: "/").last.map(String.init) ?? ""
            if let dot = clean.lastIndex(of: ".") {
                let ext = String(clean[dot...]).lowercased()
                if ext.count >= 2 && ext.count <= 6 {
                    return ext
                }
            }
            return ".jpg"
        }
    }
}
