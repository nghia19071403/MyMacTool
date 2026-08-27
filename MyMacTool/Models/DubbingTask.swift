import Foundation
import Combine

/// Đại diện cho 1 task lồng tiếng: SRT → file audio giọng đọc (VieNeu-TTS).
final class DubbingTask: Identifiable, ObservableObject, Equatable {

    let id = UUID()

    /// File SRT đầu vào
    let srtURL: URL

    @Published var status: TaskStatus = .idle
    @Published var progress: Double = 0
    @Published var statusMessage = "Sẵn sàng"

    /// Giọng đọc VieNeu-TTS
    var voice: DubbingVoice = .adam

    /// Nếu dùng giọng clone — đường dẫn file audio reference
    var clonedVoiceRef: URL?
    var clonedVoiceName: String?

    /// Process đang chạy
    var process: Process?

    init(srtURL: URL, voice: DubbingVoice = .adam) {
        self.srtURL = srtURL
        self.voice = voice
    }

    var displayName: String {
        srtURL.deletingPathExtension().lastPathComponent
    }

    var srtDisplayName: String {
        srtURL.lastPathComponent
    }

    static func == (lhs: DubbingTask, rhs: DubbingTask) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - VoiceSelection

/// Cho phép chọn giọng preset hoặc giọng đã clone
enum VoiceSelection: Hashable {
    case preset(DubbingVoice)
    case cloned(UUID)
}

// MARK: - ClonedVoice

/// Giọng đã clone từ file audio
struct ClonedVoice: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let audioPath: String  // đường dẫn file audio reference

    var audioURL: URL { URL(fileURLWithPath: audioPath) }

    init(id: UUID = UUID(), name: String, audioURL: URL) {
        self.id = id
        self.name = name
        self.audioPath = audioURL.path
    }
}

// MARK: - DubbingVoice

/// 20 giọng đọc tiếng Việt từ VieNeu-TTS v3 Turbo (48kHz, offline, tự nhiên)
enum DubbingVoice: String, CaseIterable, Identifiable {
    // Nam — Bắc
    case minhDuc = "Minh Đức"
    case phamTuyen = "Phạm Tuyên"
    case thanhBinh = "Thanh Bình"
    // Nam — Nam
    case thaiSon = "Thái Sơn"
    case xuanVinh = "Xuân Vĩnh"
    case minhTriet = "Minh Triết"
    case ducTri = "Đức Trí"
    case adam = "Adam"
    // Nam — Trung
    case quangSon = "Quang Sơn"
    // Nữ — Bắc
    case trucLy = "Trúc Ly"
    case ngocLinh = "Ngọc Linh"
    case doanTrang = "Đoan Trang"
    case maiAnh = "Mai Anh"
    case quynhAnh = "Quỳnh Anh"
    case ngocHuyen = "Ngọc Huyền"
    // Nữ — Nam
    case thucDoan = "Thục Đoan"
    case thuyDung = "Thùy Dung"
    case myDuyen = "Mỹ Duyên"
    case kimThanh = "Kim Thanh"
    // Nữ — Trung
    case ngocTran = "Ngọc Trân"

    var id: String { rawValue }

    /// Tên voice truyền cho VieNeu SDK
    var voiceName: String { rawValue }

    var displayName: String {
        switch self {
        // Nam — Bắc
        case .minhDuc: return "👨 Minh Đức (Bắc · Tin tức)"
        case .phamTuyen: return "👨 Phạm Tuyên (Bắc · Tự nhiên)"
        case .thanhBinh: return "👨 Thanh Bình (Bắc · Kể chuyện)"
        // Nam — Nam
        case .thaiSon: return "👨 Thái Sơn (Nam · Kể chuyện)"
        case .xuanVinh: return "👨 Xuân Vĩnh (Nam · Tự nhiên)"
        case .minhTriet: return "👨 Minh Triết (Nam · Tin tức)"
        case .ducTri: return "👨 Đức Trí (Nam · Đọc truyện)"
        case .adam: return "👨 Adam (Nam · Tự nhiên)"
        // Nam — Trung
        case .quangSon: return "👨 Quang Sơn (Trung · Tự nhiên)"
        // Nữ — Bắc
        case .trucLy: return "👩 Trúc Ly (Bắc · Tự nhiên)"
        case .ngocLinh: return "👩 Ngọc Linh (Bắc · Kể chuyện)"
        case .doanTrang: return "👩 Đoan Trang (Bắc · Tự nhiên)"
        case .maiAnh: return "👩 Mai Anh (Bắc · Tin tức)"
        case .quynhAnh: return "👩 Quỳnh Anh (Bắc · Đọc truyện)"
        case .ngocHuyen: return "👩 Ngọc Huyền (Bắc · Tự nhiên)"
        // Nữ — Nam
        case .thucDoan: return "👩 Thục Đoan (Nam · Kể chuyện)"
        case .thuyDung: return "👩 Thùy Dung (Nam · Tin tức)"
        case .myDuyen: return "👩 Mỹ Duyên (Nam · Đọc truyện)"
        case .kimThanh: return "👩 Kim Thanh (Nam · Đọc truyện)"
        // Nữ — Trung
        case .ngocTran: return "👩 Ngọc Trân (Trung · Tự nhiên)"
        }
    }
}


// MARK: - DubbingHistoryItem

/// Lịch sử lồng tiếng
struct DubbingHistoryItem: Identifiable, Codable {
    let id: UUID
    let srtName: String
    let voiceLabel: String
    let date: Date
    let success: Bool
    let outputPath: String?

    init(srtName: String, voiceLabel: String, success: Bool, outputPath: String? = nil) {
        self.id = UUID()
        self.srtName = srtName
        self.voiceLabel = voiceLabel
        self.date = Date()
        self.success = success
        self.outputPath = outputPath
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: date)
    }
}
