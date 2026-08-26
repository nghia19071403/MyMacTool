import SwiftUI
import Combine
import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// ViewModel chính của app. Chứa toàn bộ state và logic nghiệp vụ.
/// View chỉ hiển thị và gọi method trên ViewModel — không chứa logic.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Services

    let transcriptionService = TranscriptionService()
    let dubbingService = DubbingService.shared

    // MARK: - Init

    init() {
        // Auto-trigger dubbing khi SRT tạo xong
        transcriptionService.onSRTCreated = { [weak self] srtURL in
            self?.autoDubAfterSRT(srtURL: srtURL)
        }
    }

    // MARK: - State: Navigation

    @Published var selectedSidebarItem: SidebarItem = .platform(.bilibili)
    @Published var selectedTaskID: UUID?

    // MARK: - State: Video Tasks (tab kéo file / Whisper)

    @Published var tasks: [VideoTask] = []
    @Published var hasActiveTasks = false

    // MARK: - State: Link Download (tab Bilibili / Douyin)

    @Published var linkTexts: [LinkPlatform: String] = [
        .bilibili: "",
        .douyin: ""
    ]

    @Published var downloadTasks: [LinkPlatform: [DownloadTask]] = [
        .bilibili: [],
        .douyin: []
    ]

    // MARK: - State: Settings

    @Published var srtOutputOption: SRTOutputOption = .both

    @Published var maxConcurrentClips: Int = 2 {
        didSet { transcriptionService.maxConcurrent = maxConcurrentClips }
    }

    // MARK: - State: Dubbing (tab lồng tiếng)

    @Published var dubbingSRTURL: URL?
    @Published var dubbingVoice: DubbingVoice = .viVNFemale
    @Published var currentDubbingTask: DubbingTask?
    @Published var isPreviewingVoice: Bool = false

    // MARK: - State: UI

    @Published var isTargeted = false
    @Published var showingFileImporter = false

    // MARK: - Computed

    var selectedTask: VideoTask? {
        tasks.first { $0.id == selectedTaskID }
    }

    // MARK: - Navigation

    func onSidebarChanged() {
        selectedTaskID = nil
    }

    // MARK: - Sidebar

    func isRunning(_ item: SidebarItem) -> Bool {
        switch item {
        case .platform(let platform):
            return downloadTasks[platform]?.contains { $0.isDownloading } == true
        case .localFile:
            return tasks.contains { $0.status.isActive }
        case .dubbing:
            return currentDubbingTask?.status.isActive == true
        }
    }

    // MARK: - Video Tasks (kéo file)

    func addTask(for url: URL) {
        let task = VideoTask(url: url, srtOption: srtOutputOption)
        tasks.append(task)
        selectedTaskID = task.id
        loadVideoInfo(for: task)
    }

    func closeTask(_ task: VideoTask) {
        transcriptionService.cancel(task)
        tasks.removeAll { $0.id == task.id }
        if selectedTaskID == task.id {
            selectedTaskID = tasks.last?.id
        }
    }

    func startTask(_ task: VideoTask) {
        transcriptionService.enqueue(task)
    }

    func startAllTasks() {
        transcriptionService.enqueueAll(tasks)
        hasActiveTasks = true
    }

    func stopAll() {
        for task in tasks where task.status.isActive {
            transcriptionService.cancel(task)
        }
        hasActiveTasks = false
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    self?.addTask(for: url)
                }
            }
        }
        return true
    }

    // MARK: - Link Download

    func downloadFromLink(platform: LinkPlatform) {
        let trimmed = (linkTexts[platform] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Xóa ô nhập ngay để user dán link mới
        linkTexts[platform] = ""

        // Tạo download task mới
        let dlTask = DownloadTask(urlString: trimmed, platform: platform)
        if downloadTasks[platform] == nil { downloadTasks[platform] = [] }
        downloadTasks[platform]?.insert(dlTask, at: 0)

        // Chọn API phù hợp
        if platform == .douyin {
            downloadDouyin(task: dlTask, urlString: trimmed, platform: platform)
        } else {
            downloadYtDlp(task: dlTask, urlString: trimmed, platform: platform)
        }
    }

    func stopDownload(_ dlTask: DownloadTask) {
        dlTask.cancel()
    }

    func retryDownload(_ dlTask: DownloadTask) {
        let platform = dlTask.platform
        let urlString = dlTask.urlString
        dlTask.reset()

        if platform == .douyin {
            downloadDouyin(task: dlTask, urlString: urlString, platform: platform)
        } else {
            downloadYtDlp(task: dlTask, urlString: urlString, platform: platform)
        }
    }

    // MARK: - Dubbing

    func pickSRTFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .plainText
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Chọn file phụ đề SRT"

        if panel.runModal() == .OK {
            dubbingSRTURL = panel.url
        }
    }

    func startDubbing() {
        guard let srtURL = dubbingSRTURL else { return }

        let task = DubbingTask(srtURL: srtURL, voice: dubbingVoice)
        currentDubbingTask = task
        dubbingService.start(task)
    }

    /// Auto-trigger: gọi sau khi tạo SRT xong để tự động lồng tiếng
    func autoDubAfterSRT(srtURL: URL) {
        let task = DubbingTask(srtURL: srtURL, voice: dubbingVoice)
        currentDubbingTask = task
        selectedSidebarItem = .dubbing
        dubbingService.start(task)
    }

    func cancelDubbing() {
        guard let task = currentDubbingTask else { return }
        dubbingService.cancel(task)
    }

    func resetDubbing() {
        currentDubbingTask = nil
    }

    /// Dừng audio preview đang phát
    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    private var previewPlayer: NSSound?

    func previewVoice() {
        // Nếu đang phát → dừng
        if let player = previewPlayer, player.isPlaying {
            player.stop()
            previewPlayer = nil
            return
        }

        guard !isPreviewingVoice else { return }
        isPreviewingVoice = true

        let voice = dubbingVoice
        let rate = "+0%"

        // Câu mẫu theo ngôn ngữ
        let sampleText: String
        switch voice.language {
        case "vi":
            sampleText = "Xin chào, đây là giọng đọc mẫu để bạn nghe thử trước khi lồng tiếng."
        case "en":
            sampleText = "Hello, this is a sample voice preview so you can hear how it sounds before dubbing."
        case "zh":
            sampleText = "大家好，这是一段语音试听样本，让你听听这个声音怎么样。"
        case "ja":
            sampleText = "こんにちは、これは吹き替え前に声を確認するためのサンプルです。"
        case "ko":
            sampleText = "안녕하세요, 더빙 전에 목소리를 확인할 수 있는 샘플입니다."
        default:
            sampleText = "Xin chào, đây là giọng đọc mẫu để bạn nghe thử trước khi lồng tiếng."
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            guard let python = SystemEnvironment.shared.resolvePython() else {
                await MainActor.run { self.isPreviewingVoice = false }
                return
            }

            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice_preview_\(UUID().uuidString).mp3")

            let script = """
            import asyncio
            import edge_tts

            async def main():
                communicate = edge_tts.Communicate("\(sampleText)", "\(voice.voiceName)", rate="\(rate)", pitch="\(voice.pitch)")
                await communicate.save("\(tempFile.path)")

            asyncio.run(main())
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = ["-c", script]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    // Phát audio trực tiếp trong app bằng NSSound
                    await MainActor.run {
                        let sound = NSSound(contentsOf: tempFile, byReference: false)
                        sound?.play()
                        self.previewPlayer = sound
                        self.isPreviewingVoice = false
                    }
                    // Xóa file tạm sau 15 giây
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    try? FileManager.default.removeItem(at: tempFile)
                } else {
                    await MainActor.run { self.isPreviewingVoice = false }
                }
            } catch {
                print("❌ Preview voice error:", error)
                await MainActor.run { self.isPreviewingVoice = false }
            }
        }
    }

    // MARK: - Private: Download Douyin

    private func downloadDouyin(task dlTask: DownloadTask, urlString: String, platform: LinkPlatform) {
        let outputDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .appendingPathComponent(platform.folderName)

        let currentSrtOption = self.srtOutputOption

        DouyinSaverAPI.shared.download(
            urlString: urlString,
            outputDir: outputDir,
            onProgress: { progress, message in
                DispatchQueue.main.async {
                    guard !dlTask.isCancelled else { return }
                    dlTask.progress = progress
                    dlTask.status = message
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, !dlTask.isCancelled else { return }
                    dlTask.isDownloading = false

                    switch result {
                    case .success(let url):
                        dlTask.isCompleted = true
                        dlTask.status = "Tải xong! Đang tạo SRT..."
                        self.addVideoToWhisper(url: url, srtOption: currentSrtOption)

                    case .failure(let error):
                        dlTask.errorMessage = error.localizedDescription
                        dlTask.status = "Lỗi"
                    }
                }
            }
        )
    }

    // MARK: - Private: Download yt-dlp

    private func downloadYtDlp(task dlTask: DownloadTask, urlString: String, platform: LinkPlatform) {
        let currentSrtOption = self.srtOutputOption

        LinkDownloader.shared.download(
            urlString: urlString,
            platformFolder: platform.folderName,
            onProgress: { progress, message in
                DispatchQueue.main.async {
                    guard !dlTask.isCancelled else { return }
                    dlTask.progress = progress
                    dlTask.status = message
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, !dlTask.isCancelled else { return }
                    dlTask.isDownloading = false

                    switch result {
                    case .success(let url):
                        dlTask.isCompleted = true
                        dlTask.status = "Tải xong! Đang tạo SRT..."
                        self.addVideoToWhisper(url: url, srtOption: currentSrtOption)

                    case .failure(let error):
                        dlTask.errorMessage = error.localizedDescription
                        dlTask.status = "Lỗi"
                    }
                }
            }
        )
    }

    // MARK: - Private: Helpers

    /// Thêm video đã tải vào pipeline Whisper
    private func addVideoToWhisper(url: URL, srtOption: SRTOutputOption) {
        let videoTask = VideoTask(url: url, srtOption: srtOption)
        tasks.append(videoTask)
        loadVideoInfo(for: videoTask)
        transcriptionService.enqueue(videoTask)
    }

    /// Đọc thông tin video (duration, size)
    private func loadVideoInfo(for task: VideoTask) {
        let asset = AVAsset(url: task.url)

        Task {
            do {
                let duration = try await asset.load(.duration)
                let totalSeconds = CMTimeGetSeconds(duration)

                let hours = Int(totalSeconds) / 3600
                let minutes = (Int(totalSeconds) % 3600) / 60
                let seconds = Int(totalSeconds) % 60

                let durationText = hours > 0
                    ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                    : String(format: "%02d:%02d", minutes, seconds)

                let attributes = try FileManager.default.attributesOfItem(atPath: task.url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let sizeText = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

                await MainActor.run {
                    task.videoDuration = durationText
                    task.videoSize = sizeText
                }
            } catch {
                print("❌ Không đọc được video:", error)
            }
        }
    }
}
