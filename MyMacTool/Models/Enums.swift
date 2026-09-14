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
        case .bilibili: return "play.tv"
        case .douyin: return "music.note"
        }
    }

    var placeholder: String {
        switch self {
        case .bilibili: return "Dán link Bilibili vào đây (bilibili.com/video/BV... hoặc b23.tv/...)..."
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

// MARK: - VideoQuality

/// Chất lượng tải video (dùng cho tab Bilibili).
/// Ưu tiên codec H.264 (avc1) vì luồng AV1 của Bilibili hay bị CDN cắt kết nối.
enum VideoQuality: String, CaseIterable, Identifiable {
    case best = "Tốt nhất"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case p360 = "360p"
    case audioOnly = "Chỉ âm thanh"

    var id: String { rawValue }

    /// Chuỗi -f cho yt-dlp. Ưu tiên avc1 (H.264), fallback dần để luôn tải được.
    var formatSelector: String {
        switch self {
        case .best:
            // Cao nhất: ưu tiên H.264 (tải ổn định), rồi H.265, cuối cùng mọi codec.
            // yt-dlp tự lấy độ phân giải cao nhất trong nhóm được chọn.
            return "bv*[vcodec^=avc1]+ba/bv*[vcodec^=hvc1]+ba/bv*+ba/b"
        case .p1080:
            return "bv*[height<=1080][vcodec^=avc1]+ba/bv*[height<=1080]+ba/b[height<=1080]"
        case .p720:
            return "bv*[height<=720][vcodec^=avc1]+ba/bv*[height<=720]+ba/b[height<=720]"
        case .p480:
            return "bv*[height<=480][vcodec^=avc1]+ba/bv*[height<=480]+ba/b[height<=480]"
        case .p360:
            return "bv*[height<=360][vcodec^=avc1]+ba/bv*[height<=360]+ba/b[height<=360]"
        case .audioOnly:
            return "ba/bestaudio"
        }
    }
}

// MARK: - ProcessingSpeed

/// Tốc độ xử lý Whisper — điều khiển số luồng CPU (cpu_threads).
/// Min = như hiện tại (để faster-whisper tự quyết, thường ít luồng, máy mát).
/// Max = dùng hết số nhân của máy (nhanh nhất, máy nóng/ồn hơn).
enum ProcessingSpeed: String, CaseIterable, Identifiable {
    case min = "Tiết kiệm (mặc định)"
    case auto = "Tự động (theo máy)"
    case balanced = "Cân bằng"
    case fast = "Nhanh"
    case max = "Tối đa (dùng hết nhân)"

    var id: String { rawValue }

    /// Thông tin CPU của máy đang chạy (đọc động, khác nhau trên mỗi máy).
    private var cpu: CPUInfo { SystemEnvironment.shared.cpuInfo() }

    /// Tổng số nhân logic của máy đang chạy.
    static var coreCount: Int {
        SystemEnvironment.shared.cpuInfo().logicalCores
    }

    /// Số luồng CPU truyền cho WhisperModel(cpu_threads=...).
    /// Trả về 0 nghĩa là KHÔNG set (để thư viện tự quyết như hiện tại).
    /// Các mức khác tính động theo CPU thật của máy → chạy tối ưu trên mọi máy.
    var cpuThreads: Int {
        let info = cpu
        let cores = info.logicalCores
        switch self {
        case .min:
            return 0                                   // như hiện tại — không ép số luồng
        case .auto:
            return info.recommendedThreads             // theo máy: P-core hoặc ~3/4 nhân
        case .balanced:
            return Swift.max(2, cores / 2)             // ~nửa số nhân
        case .fast:
            return Swift.max(2, cores * 3 / 4)         // ~3/4 số nhân
        case .max:
            return cores                               // dùng hết nhân
        }
    }

    /// Mô tả ngắn hiển thị dưới dropdown — phản ánh CPU thật của máy.
    var hint: String {
        let info = cpu
        switch self {
        case .min:
            return "Máy mát, chạy nền tốt (như cũ)"
        case .auto:
            return "Tự chọn \(info.recommendedThreads) luồng cho \(info.summary)"
        case .balanced:
            return "Nhanh hơn, máy vẫn mượt (\(Swift.max(2, info.logicalCores / 2)) luồng)"
        case .fast:
            return "Nhanh, máy hơi nóng (\(Swift.max(2, info.logicalCores * 3 / 4)) luồng)"
        case .max:
            return "Nhanh nhất, dùng hết \(info.logicalCores) luồng — máy nóng/ồn"
        }
    }
}

// MARK: - SimpleError

/// Error đơn giản dùng cho các service
struct SimpleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
