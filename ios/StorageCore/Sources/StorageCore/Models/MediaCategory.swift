import Foundation

/// The kind of media an item represents. Screenshots are tracked separately from
/// photos because they are the most common cleanup candidates.
public enum MediaCategory: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case photo
    case video
    case screenshot

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .photo: "Photos"
        case .video: "Videos"
        case .screenshot: "Screenshots"
        }
    }

    public var singularTitle: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .screenshot: "Screenshot"
        }
    }
}

/// The file format of a media item. The simulated compression model uses it to
/// decide which items can be compressed.
public enum MediaFormat: String, CaseIterable, Codable, Hashable, Sendable {
    case heic
    case jpeg
    case png
    case proRAW
    case hevc
    case h264
    case proRes

    public var displayName: String {
        switch self {
        case .heic: "HEIC"
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .proRAW: "ProRAW"
        case .hevc: "HEVC"
        case .h264: "H.264"
        case .proRes: "ProRes"
        }
    }

    public var fileExtension: String {
        switch self {
        case .heic: "HEIC"
        case .jpeg: "JPG"
        case .png: "PNG"
        case .proRAW: "DNG"
        case .hevc, .h264, .proRes: "MOV"
        }
    }
}
