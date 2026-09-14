import Foundation
import Combine

/// Đại diện cho 1 video đang được quản lý.
/// Là class + ObservableObject để mỗi task tự publish thay đổi riêng.
final class VideoTask: Identifiable, ObservableObject, Equatable {

    let id = UUID()
    let url: URL

    @Published var videoDuration = ""
    @Published var videoSize = ""

    @Published var status: TaskStatus = .idle
    @Published var progress: Double = 0
    @Published var statusMessage = "Sẵn sàng"

    /// Process/Pipe của riêng task này
    var process: Process?
    var pipe: Pipe?

    /// Lựa chọn ngôn ngữ file SRT output
    var srtOutputOption: SRTOutputOption = .both

    /// Model Whisper được chọn (auto hoặc user override)
    var whisperModel: WhisperModel = .auto

    /// Số luồng CPU cho Whisper (0 = để thư viện tự quyết, như hiện tại)
    var cpuThreads: Int = 0

    init(url: URL, srtOption: SRTOutputOption = .both, whisperModel: WhisperModel = .auto, cpuThreads: Int = 0) {
        self.url = url
        self.srtOutputOption = srtOption
        self.whisperModel = whisperModel
        self.cpuThreads = cpuThreads
    }

    var displayName: String {
        url.lastPathComponent
    }

    static func == (lhs: VideoTask, rhs: VideoTask) -> Bool {
        lhs.id == rhs.id
    }
}
