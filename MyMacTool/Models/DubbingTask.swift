import Foundation
import Combine

/// Đại diện cho 1 task lồng tiếng: SRT + Video → Video có giọng đọc.
final class DubbingTask: Identifiable, ObservableObject, Equatable {

    let id = UUID()

    /// File SRT đầu vào
    let srtURL: URL

    /// File video gốc (để ghép audio vào)
    let videoURL: URL

    @Published var status: TaskStatus = .idle
    @Published var progress: Double = 0
    @Published var statusMessage = "Sẵn sàng"

    /// Giọng đọc edge-tts (mặc định giọng nữ Việt Nam)
    var voice: DubbingVoice = .viVNFemale

    /// Tốc độ đọc (ví dụ: "+0%", "+10%", "-10%")
    var speedRate: String = "+0%"

    /// Giữ audio gốc (mix) hay thay hoàn toàn
    var keepOriginalAudio: Bool = false

    /// Âm lượng audio gốc khi mix (0.0 - 1.0)
    var originalVolume: Double = 0.2

    /// Process đang chạy
    var process: Process?

    init(srtURL: URL, videoURL: URL, voice: DubbingVoice = .viVNFemale) {
        self.srtURL = srtURL
        self.videoURL = videoURL
        self.voice = voice
    }

    var displayName: String {
        videoURL.deletingPathExtension().lastPathComponent
    }

    var srtDisplayName: String {
        srtURL.lastPathComponent
    }

    static func == (lhs: DubbingTask, rhs: DubbingTask) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - DubbingVoice

/// Giọng đọc hot nhất từ edge-tts — Việt, Anh, Trung, Nhật, Hàn
enum DubbingVoice: String, CaseIterable, Identifiable {
    // 🇻🇳 Tiếng Việt
    case viVNFemale = "vi-VN-HoaiMyNeural"
    case viVNFemaleHigh = "vi-VN-HoaiMyNeural+high"
    case viVNFemaleLow = "vi-VN-HoaiMyNeural+low"
    case viVNMale = "vi-VN-NamMinhNeural"
    case viVNMaleDeep = "vi-VN-NamMinhNeural+deep"
    case viVNMaleBright = "vi-VN-NamMinhNeural+bright"
    // 🇺🇸 Tiếng Anh (hot nhất)
    case enUSAva = "en-US-AvaMultilingualNeural"
    case enUSEmma = "en-US-EmmaMultilingualNeural"
    case enUSAria = "en-US-AriaNeural"
    case enUSAna = "en-US-AnaNeural"
    case enUSAndrew = "en-US-AndrewMultilingualNeural"
    case enUSBrian = "en-US-BrianMultilingualNeural"
    case enUSJenny = "en-US-JennyNeural"
    case enUSGuy = "en-US-GuyNeural"
    // 🇨🇳 Tiếng Trung (hot nhất)
    case zhCNXiaoxiao = "zh-CN-XiaoxiaoNeural"
    case zhCNXiaoyi = "zh-CN-XiaoyiNeural"
    case zhCNYunxi = "zh-CN-YunxiNeural"
    case zhCNYunjian = "zh-CN-YunjianNeural"
    case zhCNYunyang = "zh-CN-YunyangNeural"
    // 🇯🇵 Tiếng Nhật
    case jaJPNanami = "ja-JP-NanamiNeural"
    case jaJPKeita = "ja-JP-KeitaNeural"
    // 🇰🇷 Tiếng Hàn
    case koKRSunHi = "ko-KR-SunHiNeural"
    case koKRHyunsu = "ko-KR-HyunsuMultilingualNeural"

    var id: String { rawValue }

    /// Tên voice gốc truyền cho edge-tts
    var voiceName: String {
        switch self {
        case .viVNFemale, .viVNFemaleHigh, .viVNFemaleLow:
            return "vi-VN-HoaiMyNeural"
        case .viVNMale, .viVNMaleDeep, .viVNMaleBright:
            return "vi-VN-NamMinhNeural"
        default:
            return rawValue
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
        // Việt
        case .viVNFemale: return "🇻🇳 Nữ - Hoài My (chuẩn)"
        case .viVNFemaleHigh: return "🇻🇳 Nữ - Hoài My (cao, trẻ)"
        case .viVNFemaleLow: return "🇻🇳 Nữ - Hoài My (trầm, sâu)"
        case .viVNMale: return "🇻🇳 Nam - Nam Minh (chuẩn)"
        case .viVNMaleDeep: return "🇻🇳 Nam - Nam Minh (trầm, ấm)"
        case .viVNMaleBright: return "🇻🇳 Nam - Nam Minh (cao, sáng)"
        // Anh
        case .enUSAva: return "🇺🇸 Nữ - Ava (tự nhiên, thân thiện)"
        case .enUSEmma: return "🇺🇸 Nữ - Emma (vui vẻ, hoạt ngôn)"
        case .enUSAria: return "🇺🇸 Nữ - Aria (tự tin, năng động)"
        case .enUSAna: return "🇺🇸 Nữ - Ana (dễ thương, trẻ trung)"
        case .enUSAndrew: return "🇺🇸 Nam - Andrew (ấm, tự tin)"
        case .enUSBrian: return "🇺🇸 Nam - Brian (bình dân, chân thành)"
        case .enUSJenny: return "🇺🇸 Nữ - Jenny (dịu dàng, nhẹ nhàng)"
        case .enUSGuy: return "🇺🇸 Nam - Guy (đam mê, tin tức)"
        // Trung
        case .zhCNXiaoxiao: return "🇨🇳 Nữ - Xiaoxiao (ấm áp, kể chuyện)"
        case .zhCNXiaoyi: return "🇨🇳 Nữ - Xiaoyi (hoạt ngôn, sống động)"
        case .zhCNYunxi: return "🇨🇳 Nam - Yunxi (trẻ trung, sáng)"
        case .zhCNYunjian: return "🇨🇳 Nam - Yunjian (mạnh mẽ, đam mê)"
        case .zhCNYunyang: return "🇨🇳 Nam - Yunyang (MC, chuyên nghiệp)"
        // Nhật
        case .jaJPNanami: return "🇯🇵 Nữ - Nanami (dịu dàng)"
        case .jaJPKeita: return "🇯🇵 Nam - Keita (thân thiện)"
        // Hàn
        case .koKRSunHi: return "🇰🇷 Nữ - Sun-Hi (thân thiện)"
        case .koKRHyunsu: return "🇰🇷 Nam - Hyunsu (ấm áp)"
        }
    }

    var language: String {
        switch self {
        case .viVNFemale, .viVNFemaleHigh, .viVNFemaleLow,
             .viVNMale, .viVNMaleDeep, .viVNMaleBright:
            return "vi"
        case .enUSAva, .enUSEmma, .enUSAria, .enUSAna,
             .enUSAndrew, .enUSBrian, .enUSJenny, .enUSGuy:
            return "en"
        case .zhCNXiaoxiao, .zhCNXiaoyi, .zhCNYunxi, .zhCNYunjian, .zhCNYunyang:
            return "zh"
        case .jaJPNanami, .jaJPKeita:
            return "ja"
        case .koKRSunHi, .koKRHyunsu:
            return "ko"
        }
    }
}
