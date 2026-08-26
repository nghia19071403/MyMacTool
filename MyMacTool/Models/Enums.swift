import Foundation

// MARK: - TaskStatus

/// Trạng thái xử lý của một video task
enum TaskStatus: Equatable {
    case idle
    case queued
    case running
    case done
    case error(String)

    var isActive: Bool {
        self == .queued || self == .running
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - SRTOutputOption

/// Cho phép user chọn tạo file SRT nào sau khi Whisper xử lý xong.
enum SRTOutputOption: String, CaseIterable, Identifiable {
    case originalOnly = "Chỉ gốc (中文)"
    case translatedOnly = "Chỉ dịch (Tiếng Việt)"
    case both = "Cả 2 (中文 + Tiếng Việt)"

    var id: String { rawValue }

    /// Có cần giữ file SRT gốc không
    var keepOriginal: Bool {
        self == .originalOnly || self == .both
    }

    /// Có cần dịch sang tiếng Việt không
    var needsTranslation: Bool {
        self == .translatedOnly || self == .both
    }
}

// MARK: - LinkPlatform

/// Nền tảng video hỗ trợ dán link tải
enum LinkPlatform: String, CaseIterable, Identifiable {
    case bilibili = "Bilibili"
    case douyin = "Douyin"

    var id: String { rawValue }

    /// Tên thư mục con trong ~/Downloads/ để lưu video
    var folderName: String { rawValue }

    var icon: String {
        switch self {
        case .bilibili: return "play.tv.fill"
        case .douyin: return "music.note"
        }
    }

    var placeholder: String {
        switch self {
        case .bilibili: return "Dán link video Bilibili vào đây..."
        case .douyin: return "Dán link Douyin vào đây (v.douyin.com/xxxxx)..."
        }
    }
}

// MARK: - SidebarItem

/// 4 mục sidebar: 2 tab dán link + 1 tab kéo file + 1 tab lồng tiếng
enum SidebarItem: Hashable, Identifiable, CaseIterable {
    case platform(LinkPlatform)
    case localFile
    case dubbing

    static var allCases: [SidebarItem] {
        LinkPlatform.allCases.map { .platform($0) } + [.localFile, .dubbing]
    }

    var id: String {
        switch self {
        case .platform(let p): return p.id
        case .localFile: return "localFile"
        case .dubbing: return "dubbing"
        }
    }

    var title: String {
        switch self {
        case .platform(let p): return p.rawValue
        case .localFile: return "Kéo file"
        case .dubbing: return "Lồng tiếng"
        }
    }

    var icon: String {
        switch self {
        case .platform(let p): return p.icon
        case .localFile: return "folder.badge.plus"
        case .dubbing: return "waveform.circle.fill"
        }
    }
}

// MARK: - YtDlpMethod

/// Cách gọi yt-dlp: binary cài riêng hoặc chạy qua python module
enum YtDlpMethod {
    case binary(String)
    case pythonModule(python: String)
}

// MARK: - WhisperModel

/// Model Whisper để nhận dạng giọng nói.
/// Tự động chọn model phù hợp theo thời lượng video.
enum WhisperModel: String, CaseIterable, Identifiable {
    case auto = "Tự động (theo thời lượng)"
    case tiny = "tiny — Rất nhanh, OK"
    case base = "base — Nhanh, khá tốt"
    case small = "small — Cân bằng"
    case medium = "medium — Chậm, rất tốt"

    var id: String { rawValue }

    /// Tên model truyền cho Whisper CLI
    var modelName: String {
        switch self {
        case .auto: return "small" // fallback
        case .tiny: return "tiny"
        case .base: return "base"
        case .small: return "small"
        case .medium: return "medium"
        }
    }

    /// Tự chọn model theo thời lượng video (giây).
    /// Video ngắn → model nhẹ (nhanh). Video dài → model tốt hơn (chính xác).
    static func recommend(forDuration seconds: Double) -> String {
        switch seconds {
        case ..<300:    return "tiny"    // < 5 phút → tiny (siêu nhanh)
        case ..<900:    return "base"    // 5-15 phút → base
        case ..<3600:   return "small"   // 15-60 phút → small
        default:        return "medium"  // > 60 phút → medium
        }
    }
}

// MARK: - SimpleError

/// Error đơn giản dùng cho các service
struct SimpleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
