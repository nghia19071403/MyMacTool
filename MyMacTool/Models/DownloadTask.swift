import Foundation
import Combine

/// Đại diện cho 1 link đang được tải về.
/// Mỗi link = 1 instance riêng, chạy song song.
final class DownloadTask: Identifiable, ObservableObject {

    let id = UUID()
    let urlString: String
    let platform: LinkPlatform

    @Published var progress: Double = 0
    @Published var status: String = "Đang bắt đầu..."
    @Published var isDownloading: Bool = true
    @Published var isCompleted: Bool = false
    @Published var errorMessage: String?

    /// Flag báo cancel cho closure callback
    var isCancelled: Bool = false

    init(urlString: String, platform: LinkPlatform) {
        self.urlString = urlString
        self.platform = platform
    }

    var displayName: String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 40 {
            return String(trimmed.prefix(40)) + "..."
        }
        return trimmed
    }

    /// Dừng task đang tải
    func cancel() {
        isCancelled = true
        isDownloading = false
        errorMessage = "Đã dừng"
        status = "Đã dừng"
    }

    /// Reset để chạy lại
    func reset() {
        isCancelled = false
        isDownloading = true
        isCompleted = false
        errorMessage = nil
        progress = 0
        status = "Đang bắt đầu..."
    }
}
