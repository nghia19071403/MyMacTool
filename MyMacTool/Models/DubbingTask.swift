import Foundation
import Combine

/// Đại diện cho 1 task lồng tiếng: SRT → file audio giọng đọc.
final class DubbingTask: Identifiable, ObservableObject, Equatable {

    let id = UUID()

    /// File SRT đầu vào
    let srtURL: URL

    @Published var status: TaskStatus = .idle
    @Published var progress: Double = 0
    @Published var statusMessage = "Sẵn sàng"

    /// Giọng đọc edge-tts
    var voice: DubbingVoice = .viVNFemale

    /// Process đang chạy
    var process: Process?

    init(srtURL: URL, voice: DubbingVoice = .viVNFemale) {
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

// MARK: - DubbingVoice

/// Giọng đọc tiếng Việt từ edge-tts
enum DubbingVoice: String, CaseIterable, Identifiable {
    // 🇻🇳 Tiếng Việt
    case viVNFemale = "vi-VN-HoaiMyNeural"
    case viVNFemaleHigh = "vi-VN-HoaiMyNeural+high"
    case viVNFemaleLow = "vi-VN-HoaiMyNeural+low"
    case viVNMale = "vi-VN-NamMinhNeural"
    case viVNMaleDeep = "vi-VN-NamMinhNeural+deep"
    case viVNMaleBright = "vi-VN-NamMinhNeural+bright"

    var id: String { rawValue }

    /// Tên voice gốc truyền cho edge-tts
    var voiceName: String {
        switch self {
        case .viVNFemale, .viVNFemaleHigh, .viVNFemaleLow:
            return "vi-VN-HoaiMyNeural"
        case .viVNMale, .viVNMaleDeep, .viVNMaleBright:
            return "vi-VN-NamMinhNeural"
        }
    }

    /// Pitch offset — thay đổi tông giọng
    var pitch: String {
        switch self {
        case .viVNFemaleHigh: return "+30Hz"
        case .viVNFemaleLow: return "-20Hz"
        case .viVNMaleDeep: return "-30Hz"
        case .viVNMaleBright: return "+25Hz"
        default: return "+0Hz"
        }
    }

    var displayName: String {
        switch self {
        case .viVNFemale: return "Nữ - Hoài My (chuẩn)"
        case .viVNFemaleHigh: return "Nữ - Hoài My (cao, trẻ)"
        case .viVNFemaleLow: return "Nữ - Hoài My (trầm, sâu)"
        case .viVNMale: return "Nam - Nam Minh (chuẩn)"
        case .viVNMaleDeep: return "Nam - Nam Minh (trầm, ấm)"
        case .viVNMaleBright: return "Nam - Nam Minh (cao, sáng)"
        }
    }
}
