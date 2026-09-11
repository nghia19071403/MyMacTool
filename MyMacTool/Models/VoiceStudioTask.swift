import Foundation
import Combine

/// Đại diện cho 1 task lồng tiếng qua VoiceStudio: SRT → file audio.
/// Tách biệt hoàn toàn với DubbingTask (VieNeu-TTS).
final class VoiceStudioTask: Identifiable, ObservableObject, Equatable {

    let id = UUID()

    /// File SRT đầu vào
    let srtURL: URL

    /// Tên giọng gửi cho VoiceStudio API
    var voice: String

    @Published var status: TaskStatus = .idle
    @Published var progress: Double = 0
    @Published var statusMessage = "Sẵn sàng"

    /// Cờ hủy — service kiểm tra giữa các lần gọi API
    var isCancelled = false

    init(srtURL: URL, voice: String) {
        self.srtURL = srtURL
        self.voice = voice
    }

    var displayName: String {
        srtURL.deletingPathExtension().lastPathComponent
    }

    var srtDisplayName: String {
        srtURL.lastPathComponent
    }

    static func == (lhs: VoiceStudioTask, rhs: VoiceStudioTask) -> Bool {
        lhs.id == rhs.id
    }
}
