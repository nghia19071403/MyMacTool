import Foundation

/// 1 video hot lấy từ Bilibili popular API.
struct TrendingVideo: Identifiable, Codable, Hashable {
    let id: String          // bvid
    let title: String       // tiêu đề gốc (tiếng Trung)
    let titleVi: String?    // tiêu đề dịch tiếng Việt (nếu có)
    let author: String      // tên up-loader
    let view: Int           // lượt xem
    let tname: String       // phân loại (tag khu vực)
    let url: String         // link video

    var viewFormatted: String {
        if view >= 10_000 {
            return String(format: "%.1f万", Double(view) / 10_000)
        }
        return "\(view)"
    }
}

/// 1 chủ đề thịnh hành do GPT gom cụm.
struct TrendingTopic: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String            // tên chủ đề (tiếng Việt)
    let keywords: [String]      // từ khóa nổi bật
    let videoCount: Int         // số video thuộc chủ đề
    let summary: String         // mô tả ngắn vì sao hot
}

/// 1 từ khóa hot lấy từ Douyin hot-search billboard.
struct TrendingKeyword: Identifiable, Codable, Hashable {
    var id: String { word }
    let word: String        // từ khóa gốc (tiếng Trung)
    let wordVi: String?     // dịch tiếng Việt (nếu có)
    let hotValue: Int       // điểm nóng

    var hotFormatted: String {
        if hotValue >= 10_000 {
            return String(format: "%.1f万", Double(hotValue) / 10_000)
        }
        return "\(hotValue)"
    }
}

/// Kết quả phân tích xu hướng.
struct TrendingResult {
    let videos: [TrendingVideo]     // Bilibili: video hot (đã dịch tiêu đề)
    let keywords: [TrendingKeyword] // Douyin: từ khóa hot (đã dịch)
    let topics: [TrendingTopic]     // top chủ đề GPT phân tích
    let generatedAt: Date

    init(videos: [TrendingVideo] = [], keywords: [TrendingKeyword] = [],
         topics: [TrendingTopic] = [], generatedAt: Date = Date()) {
        self.videos = videos
        self.keywords = keywords
        self.topics = topics
        self.generatedAt = generatedAt
    }
}

/// Nguồn xu hướng
enum TrendingSource: String, CaseIterable, Identifiable {
    case bilibili = "Bilibili"
    case douyin = "Douyin"
    var id: String { rawValue }
}

/// Toàn bộ state của 1 nguồn xu hướng — để Bilibili và Douyin giữ dữ liệu riêng.
struct TrendingState {
    var videos: [TrendingVideo] = []
    var keywords: [TrendingKeyword] = []
    var topics: [TrendingTopic] = []
    var isLoading: Bool = false
    var statusMessage: String = "Bấm để lấy xu hướng"
    var generatedAt: Date?

    var isEmpty: Bool { videos.isEmpty && keywords.isEmpty }
}
