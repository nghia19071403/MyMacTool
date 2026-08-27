import SwiftUI
import Combine
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications

/// ViewModel chính của app. Chứa toàn bộ state và logic nghiệp vụ.
/// View chỉ hiển thị và gọi method trên ViewModel — không chứa logic.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Services

    let transcriptionService = TranscriptionService()
    let dubbingService = DubbingService.shared

    // MARK: - Init

    init() {
        // Reset cache để luôn dùng đúng Python (~/whisper-env)
        SystemEnvironment.shared.resetCache()

        // Xin quyền notification
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Auto-trigger dubbing khi SRT tạo xong
        transcriptionService.onSRTCreated = { [weak self] srtURL in
            self?.autoDubAfterSRT(srtURL: srtURL)
            self?.sendNotification(title: "Tạo SRT hoàn tất ✅", body: srtURL.lastPathComponent)
        }

        // Notification khi Whisper lỗi
        transcriptionService.onTaskFailed = { [weak self] fileName, message in
            self?.sendNotification(title: "Tạo SRT thất bại ❌", body: "\(fileName): \(message)")
        }

        // Lưu lịch sử khi dubbing xong
        dubbingService.onTaskCompleted = { [weak self] task, success, outputPath in
            let voiceLabel = task.clonedVoiceName ?? task.voice.displayName
            self?.addDubbingHistoryItem(
                srtName: task.srtDisplayName,
                voiceLabel: voiceLabel,
                success: success,
                outputPath: outputPath
            )
            // Notification
            if success {
                self?.sendNotification(title: "Lồng tiếng hoàn tất ✅", body: "\(task.srtDisplayName) — giọng \(voiceLabel)")
            } else {
                self?.sendNotification(title: "Lồng tiếng thất bại ❌", body: task.srtDisplayName)
            }
        }
        // Load OpenAI key đã lưu
        openaiAPIKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        openaiModel = UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4o-mini"

        // Load giọng đã clone
        loadClonedVoices()
        loadDubbingHistory()

        // Nếu có giọng clone → mặc định chọn giọng clone đầu tiên
        if let firstClone = clonedVoices.first {
            dubbingVoiceSelection = .cloned(firstClone.id)
        }
    }

    // MARK: - Notification

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - State: Navigation

    @Published var selectedSidebarItem: SidebarItem = .platform(.douyin)
    @Published var selectedTaskID: UUID?

    // MARK: - State: Video Tasks (tab kéo file / Whisper)

    @Published var tasks: [VideoTask] = []
    @Published var hasActiveTasks = false

    // MARK: - State: Link Download (tab Douyin)

    @Published var linkTexts: [LinkPlatform: String] = [
        .douyin: ""
    ]

    @Published var downloadTasks: [LinkPlatform: [DownloadTask]] = [
        .douyin: []
    ]

    // MARK: - State: Settings

    @Published var srtOutputOption: SRTOutputOption = .translatedOnly

    // OpenAI settings cho dịch
    @Published var openaiAPIKey: String = "" {
        didSet { SRTTranslator.shared.openaiAPIKey = openaiAPIKey }
    }
    @Published var openaiModel: String = "gpt-4o-mini" {
        didSet { SRTTranslator.shared.openaiModel = openaiModel }
    }

    @Published var maxConcurrentClips: Int = 2 {
        didSet { transcriptionService.maxConcurrent = maxConcurrentClips }
    }

    // MARK: - State: Dubbing (tab lồng tiếng)

    @Published var dubbingSRTURL: URL?
    @Published var dubbingVoice: DubbingVoice = .adam
    @Published var dubbingVoiceSelection: VoiceSelection = .preset(.adam)
    @Published var currentDubbingTask: DubbingTask?
    @Published var isPreviewingVoice: Bool = false

    // Clone voice
    @Published var cloneRefAudioURL: URL?
    @Published var cloneVoiceName: String = ""
    @Published var clonedVoices: [ClonedVoice] = []
    @Published var isCloning: Bool = false
    @Published var cloneStatusMessage: String = ""
    @Published var clonePreviewReady: Bool = false

    // History
    @Published var dubbingHistory: [DubbingHistoryItem] = []

    // Tạm giữ data clone chờ user confirm
    private var pendingClonedVoice: ClonedVoice?
    private var clonePreviewAudioURL: URL?

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

        let task: DubbingTask
        switch dubbingVoiceSelection {
        case .preset(let voice):
            task = DubbingTask(srtURL: srtURL, voice: voice)
        case .cloned(let id):
            if let cloned = clonedVoices.first(where: { $0.id == id }) {
                task = DubbingTask(srtURL: srtURL, voice: .adam)
                task.clonedVoiceRef = cloned.audioURL
                task.clonedVoiceName = cloned.name
            } else {
                task = DubbingTask(srtURL: srtURL, voice: .adam)
            }
        }
        currentDubbingTask = task
        dubbingService.start(task)
    }

    /// Auto-trigger: gọi sau khi tạo SRT xong để tự động lồng tiếng
    /// Ưu tiên dùng giọng clone đầu tiên, nếu không có thì dùng giọng đang chọn
    func autoDubAfterSRT(srtURL: URL) {
        let task: DubbingTask
        if let firstClone = clonedVoices.first {
            // Ưu tiên giọng clone
            task = DubbingTask(srtURL: srtURL, voice: .adam)
            task.clonedVoiceRef = firstClone.audioURL
            task.clonedVoiceName = firstClone.name
        } else {
            // Fallback giọng preset đang chọn
            switch dubbingVoiceSelection {
            case .preset(let voice):
                task = DubbingTask(srtURL: srtURL, voice: voice)
            case .cloned(let id):
                if let cloned = clonedVoices.first(where: { $0.id == id }) {
                    task = DubbingTask(srtURL: srtURL, voice: .adam)
                    task.clonedVoiceRef = cloned.audioURL
                    task.clonedVoiceName = cloned.name
                } else {
                    task = DubbingTask(srtURL: srtURL, voice: .adam)
                }
            }
        }
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

    // MARK: - Clone Voice

    func pickCloneAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Chọn file audio mẫu (3-8 giây)"

        if panel.runModal() == .OK {
            cloneRefAudioURL = panel.url
        }
    }

    func cloneVoice() {
        guard let refURL = cloneRefAudioURL else { return }
        let name = cloneVoiceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCloning = true
        cloneStatusMessage = "Đang clone giọng nói..."

        guard let python = SystemEnvironment.shared.resolvePython() else {
            cloneStatusMessage = "Lỗi: Không tìm thấy Python3"
            isCloning = false
            return
        }

        // Copy audio ref vào thư mục app support để lưu lâu dài
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyMacTool/ClonedVoices", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let destAudio = appSupport.appendingPathComponent("\(UUID().uuidString)_\(refURL.lastPathComponent)")
        try? FileManager.default.copyItem(at: refURL, to: destAudio)

        // Test clone bằng VieNeu để verify
        let scriptFile = FileManager.default.temporaryDirectory.appendingPathComponent("clone_test.py")
        let testOutput = FileManager.default.temporaryDirectory.appendingPathComponent("clone_test.wav")

        let script = """
        from vieneu import Vieneu
        vieneu = Vieneu()
        # Test clone — nếu file audio hợp lệ sẽ tạo được audio
        audio = vieneu.infer("Xin chào, giọng nói đã được clone thành công.", ref_audio=r"\(destAudio.path)")
        vieneu.save(audio, r"\(testOutput.path)")
        print("OK")
        """

        try? script.write(to: scriptFile, atomically: true, encoding: .utf8)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [scriptFile.path]

            var env = ProcessInfo.processInfo.environment
            let currentPath = env["PATH"] ?? ""
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: scriptFile)
                // Giữ testOutput làm preview audio (sẽ xóa sau khi user quyết định)

                await MainActor.run {
                    if process.terminationStatus == 0 {
                        // Không add ngay — cho user nghe thử trước
                        let cloned = ClonedVoice(name: name, audioURL: destAudio)
                        self.pendingClonedVoice = cloned
                        self.clonePreviewAudioURL = testOutput
                        self.clonePreviewReady = true
                        self.cloneStatusMessage = "Clone thành công! Nghe thử rồi quyết định thêm vào danh sách."
                    } else {
                        let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? ""
                        print("❌ Clone voice failed: \(errMsg.suffix(300))")
                        self.cloneStatusMessage = "Lỗi: Clone thất bại. Kiểm tra file audio (cần 3-8s, rõ giọng)."
                        try? FileManager.default.removeItem(at: testOutput)
                    }
                    self.isCloning = false
                }
            } catch {
                await MainActor.run {
                    self.cloneStatusMessage = "Lỗi: \(error.localizedDescription)"
                    self.isCloning = false
                }
            }
        }
    }

    func removeClonedVoice(_ voice: ClonedVoice) {
        clonedVoices.removeAll { $0.id == voice.id }
        try? FileManager.default.removeItem(at: voice.audioURL)
        if case .cloned(let id) = dubbingVoiceSelection, id == voice.id {
            dubbingVoiceSelection = .preset(.adam)
        }
        saveClonedVoices()
    }

    func playClonePreview() {
        guard let audioURL = clonePreviewAudioURL else { return }
        let sound = NSSound(contentsOf: audioURL, byReference: false)
        sound?.play()
        previewPlayer = sound
    }

    func confirmAddClonedVoice() {
        guard let cloned = pendingClonedVoice else { return }
        clonedVoices.append(cloned)
        dubbingVoiceSelection = .cloned(cloned.id)
        cloneStatusMessage = "Đã thêm giọng \"\(cloned.name)\" vào danh sách!"
        cloneVoiceName = ""
        clonePreviewReady = false
        pendingClonedVoice = nil
        // Xóa file preview tạm
        if let previewURL = clonePreviewAudioURL {
            try? FileManager.default.removeItem(at: previewURL)
        }
        clonePreviewAudioURL = nil
        saveClonedVoices()
    }

    func discardClonePreview() {
        // Bỏ qua — xóa file đã clone nhưng giữ lại input để clone lại
        if let cloned = pendingClonedVoice {
            try? FileManager.default.removeItem(at: cloned.audioURL)
        }
        if let previewURL = clonePreviewAudioURL {
            try? FileManager.default.removeItem(at: previewURL)
        }
        pendingClonedVoice = nil
        clonePreviewAudioURL = nil
        clonePreviewReady = false
        cloneStatusMessage = "Đã bỏ qua. Bạn có thể clone lại."
    }

    // Persist cloned voices
    private func saveClonedVoices() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyMacTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let url = appSupport.appendingPathComponent("cloned_voices.json")
        if let data = try? JSONEncoder().encode(clonedVoices) {
            try? data.write(to: url)
        }
    }

    private func loadClonedVoices() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyMacTool/cloned_voices.json")
        if let data = try? Data(contentsOf: url),
           let voices = try? JSONDecoder().decode([ClonedVoice].self, from: data) {
            clonedVoices = voices.filter { FileManager.default.fileExists(atPath: $0.audioPath) }
        }
    }

    // MARK: - Dubbing History

    func addDubbingHistoryItem(srtName: String, voiceLabel: String, success: Bool, outputPath: String? = nil) {
        let item = DubbingHistoryItem(srtName: srtName, voiceLabel: voiceLabel, success: success, outputPath: outputPath)
        dubbingHistory.insert(item, at: 0) // Mới nhất lên đầu
        if dubbingHistory.count > 50 { dubbingHistory = Array(dubbingHistory.prefix(50)) }
        saveDubbingHistory()
    }

    func removeDubbingHistoryItem(_ item: DubbingHistoryItem) {
        dubbingHistory.removeAll { $0.id == item.id }
        saveDubbingHistory()
    }

    func clearDubbingHistory() {
        dubbingHistory.removeAll()
        saveDubbingHistory()
    }

    private func saveDubbingHistory() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyMacTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let url = appSupport.appendingPathComponent("dubbing_history.json")
        if let data = try? JSONEncoder().encode(dubbingHistory) {
            try? data.write(to: url)
        }
    }

    private func loadDubbingHistory() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyMacTool/dubbing_history.json")
        if let data = try? Data(contentsOf: url),
           let items = try? JSONDecoder().decode([DubbingHistoryItem].self, from: data) {
            dubbingHistory = items
        }
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

        let voiceSelection = dubbingVoiceSelection

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            guard let python = SystemEnvironment.shared.resolvePython() else {
                await MainActor.run { self.isPreviewingVoice = false }
                return
            }

            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice_preview.wav")
            let scriptFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview_voice.py")

            let script: String
            switch voiceSelection {
            case .preset(let voice):
                script = """
                from vieneu import Vieneu
                vieneu = Vieneu()
                audio = vieneu.infer("Xin chào, đây là giọng đọc mẫu để bạn nghe thử trước khi lồng tiếng.", voice="\(voice.voiceName)")
                vieneu.save(audio, r"\(tempFile.path)")
                print("OK")
                """
            case .cloned(let id):
                let refPath = await MainActor.run { self.clonedVoices.first(where: { $0.id == id })?.audioPath ?? "" }
                script = """
                from vieneu import Vieneu
                vieneu = Vieneu()
                audio = vieneu.infer("Xin chào, đây là giọng đọc mẫu để bạn nghe thử trước khi lồng tiếng.", ref_audio=r"\(refPath)")
                vieneu.save(audio, r"\(tempFile.path)")
                print("OK")
                """
            }

            try? script.write(to: scriptFile, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [scriptFile.path]

            var env = ProcessInfo.processInfo.environment
            let currentPath = env["PATH"] ?? ""
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                // Cleanup script file
                try? FileManager.default.removeItem(at: scriptFile)

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
                    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? ""
                    print("❌ Preview voice failed: \(errMsg.suffix(300))")
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
