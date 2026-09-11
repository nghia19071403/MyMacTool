import Foundation
import AppKit

/// Dịch vụ lồng tiếng qua VoiceStudio (chạy local, OpenAI-compatible API).
///
/// Khác VieNeu-TTS (chạy Python SDK trực tiếp), VoiceStudio là một app chạy
/// server local. Service này gọi HTTP tới endpoint tương thích OpenAI:
///   POST {baseURL}/v1/audio/speech
///   body JSON: { "model": ..., "voice": ..., "input": ..., "response_format": "wav" }
///   trả về audio bytes.
///
/// Quy trình lồng tiếng theo SRT:
/// 1. Parse SRT (thuần Swift) lấy start/end/text từng câu
/// 2. Gọi API cho từng câu → nhận audio WAV
/// 3. Ghép các đoạn theo timestamp bằng ffmpeg → 1 file WAV output
///
/// LƯU Ý: base URL / path / tên field có thể cần khớp với API thật của bản
/// VoiceStudio bạn cài. Các giá trị mặc định theo chuẩn OpenAI audio API.
final class VoiceStudioService {

    static let shared = VoiceStudioService()
    private init() {}

    private let queue = DispatchQueue(label: "voicestudio-service", qos: .userInitiated)

    /// Base URL của VoiceStudio server (có thể cấu hình từ UI).
    var baseURL: String = "http://127.0.0.1:8000"

    /// Model / voice mặc định (khớp với VoiceStudio; cấu hình từ UI).
    var model: String = "tts-1"

    /// Callback khi task hoàn tất — để lưu history.
    var onTaskCompleted: ((VoiceStudioTask, Bool, String?) -> Void)?

    // MARK: - Health Check

    /// Kiểm tra server VoiceStudio có đang chạy không.
    /// Thử GET {baseURL}/v1/models (endpoint chuẩn OpenAI-compatible).
    func checkServer(baseURL: String, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            completion(false, "URL không hợp lệ")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, "Không kết nối được: \(error.localizedDescription)")
                    return
                }
                if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                    // 2xx/4xx đều nghĩa là server đang sống (4xx có thể do auth)
                    completion(true, "VoiceStudio đang chạy (HTTP \(http.statusCode))")
                } else {
                    completion(false, "Server không phản hồi hợp lệ")
                }
            }
        }.resume()
    }

    // MARK: - Start Dubbing

    func start(_ task: VoiceStudioTask) {
        DispatchQueue.main.async {
            task.status = .running
            task.progress = 0
            task.statusMessage = "Đang chuẩn bị..."
        }
        queue.async { [weak self] in
            self?.execute(task)
        }
    }

    func enqueue(_ task: VoiceStudioTask) {
        DispatchQueue.main.async {
            task.status = .queued
            task.progress = 0
            task.statusMessage = "Đang chờ trong hàng đợi..."
        }
        queue.async { [weak self] in
            DispatchQueue.main.async {
                task.status = .running
                task.statusMessage = "Đang chuẩn bị..."
            }
            self?.execute(task)
        }
    }

    func cancel(_ task: VoiceStudioTask) {
        task.isCancelled = true
        DispatchQueue.main.async {
            task.status = .idle
            task.statusMessage = "Đã hủy"
        }
    }

    // MARK: - Execute

    private func execute(_ task: VoiceStudioTask) {
        guard FileManager.default.fileExists(atPath: task.srtURL.path) else {
            fail(task, message: "Không tìm thấy file SRT: \(task.srtURL.lastPathComponent)")
            return
        }

        // 1. Parse SRT
        updateStatus(task, progress: 0.02, message: "Đang đọc file SRT...")
        let segments: [SRTSegment]
        do {
            segments = try Self.parseSRT(task.srtURL)
        } catch {
            fail(task, message: "Không đọc được SRT: \(error.localizedDescription)")
            return
        }
        guard !segments.isEmpty else {
            fail(task, message: "File SRT rỗng")
            return
        }

        // 2. Thư mục làm việc tạm
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicestudio_\(task.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 3. Gọi API cho từng câu → lưu WAV
        var segmentFiles: [(start: Double, path: URL)] = []
        let total = segments.count

        for (i, seg) in segments.enumerated() {
            if task.isCancelled { return }

            let segURL = tmpDir.appendingPathComponent("seg_\(i).wav")
            let result = synthesize(text: seg.text, voice: task.voice, outputURL: segURL)

            switch result {
            case .success:
                segmentFiles.append((start: seg.start, path: segURL))
            case .failure(let err):
                fail(task, message: "Lỗi gọi VoiceStudio (câu \(i + 1)): \(err)")
                return
            }

            let progress = 0.05 + (Double(i + 1) / Double(total)) * 0.80
            updateStatus(task, progress: progress, message: "Đang tạo giọng \(i + 1)/\(total)...")
        }

        if task.isCancelled { return }
        guard !segmentFiles.isEmpty else {
            fail(task, message: "Không tạo được đoạn audio nào")
            return
        }

        // 4. Ghép theo timeline bằng ffmpeg
        updateStatus(task, progress: 0.90, message: "Đang ghép audio...")
        let outputDir = task.srtURL.deletingLastPathComponent()
        let baseName = task.srtURL.deletingPathExtension().lastPathComponent
        let outputPath = outputDir.appendingPathComponent("\(baseName)_voicestudio.wav")

        let mixed = mixTimeline(segments: segmentFiles, output: outputPath, tmpDir: tmpDir)
        guard mixed else {
            fail(task, message: "Ghép audio thất bại (kiểm tra ffmpeg)")
            return
        }

        DispatchQueue.main.async {
            task.progress = 1.0
            task.statusMessage = "Hoàn tất! File audio đã được tạo."
            task.status = .done
            self.onTaskCompleted?(task, true, outputPath.path)
            NSWorkspace.shared.open(outputDir)
        }
    }

    // MARK: - Synthesize 1 câu qua API

    private enum SynthResult {
        case success
        case failure(String)
    }

    /// Gọi POST {baseURL}/v1/audio/speech, lưu audio trả về ra file.
    /// Chạy đồng bộ (semaphore) vì đang ở background queue.
    private func synthesize(text: String, voice: String, outputURL: URL) -> SynthResult {
        guard let url = URL(string: "\(baseURL)/v1/audio/speech") else {
            return .failure("URL không hợp lệ: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "voice": voice,
            "input": text,
            "response_format": "wav"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        var result: SynthResult = .failure("Không có phản hồi")

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                result = .failure(error.localizedDescription)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure("Phản hồi không hợp lệ")
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure("HTTP \(http.statusCode) \(msg.prefix(200))")
                return
            }
            guard let data = data, !data.isEmpty else {
                result = .failure("Audio rỗng")
                return
            }
            do {
                try data.write(to: outputURL)
                result = .success
            } catch {
                result = .failure("Ghi file lỗi: \(error.localizedDescription)")
            }
        }.resume()

        semaphore.wait()
        return result
    }

    // MARK: - Ghép audio theo timeline (ffmpeg)

    /// Đặt mỗi đoạn audio vào đúng thời điểm `start` rồi trộn thành 1 file.
    /// Dùng ffmpeg filter adelay + amix.
    private func mixTimeline(segments: [(start: Double, path: URL)],
                             output: URL,
                             tmpDir: URL) -> Bool {
        guard let ffmpeg = SystemEnvironment.shared.resolveFFmpeg() else {
            print("❌ VoiceStudio: không tìm thấy ffmpeg")
            return false
        }

        // Xây lệnh ffmpeg: mỗi input được delay tới start (ms), rồi amix tất cả.
        var args: [String] = ["-y"]
        for seg in segments {
            args += ["-i", seg.path.path]
        }

        var filterParts: [String] = []
        var mixInputs: [String] = []
        for (i, seg) in segments.enumerated() {
            let delayMs = Int(seg.start * 1000)
            filterParts.append("[\(i)]adelay=\(delayMs)|\(delayMs)[a\(i)]")
            mixInputs.append("[a\(i)]")
        }
        let amix = "\(mixInputs.joined())amix=inputs=\(segments.count):normalize=0[out]"
        let filterComplex = (filterParts + [amix]).joined(separator: ";")

        args += [
            "-filter_complex", filterComplex,
            "-map", "[out]",
            "-ar", "48000",
            output.path
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.environment = SystemEnvironment.pythonEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("❌ VoiceStudio ffmpeg error:", error)
            return false
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ task: VoiceStudioTask, progress: Double, message: String) {
        DispatchQueue.main.async {
            task.progress = min(max(progress, 0), 1)
            task.statusMessage = message
        }
    }

    private func fail(_ task: VoiceStudioTask, message: String) {
        DispatchQueue.main.async {
            task.status = .error(message)
            task.statusMessage = "Lỗi: \(message)"
            self.onTaskCompleted?(task, false, nil)
        }
    }

    // MARK: - SRT Parser (thuần Swift)

    struct SRTSegment {
        let start: Double
        let end: Double
        let text: String
    }

    static func parseSRT(_ url: URL) throws -> [SRTSegment] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let blocks = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        var segments: [SRTSegment] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 3 else { continue }

            // Dòng chứa timestamp có "-->"
            guard let tsLine = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = tsLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = timestampToSeconds(parts[0]),
                  let end = timestampToSeconds(parts[1]) else { continue }

            // Text là các dòng sau dòng timestamp
            guard let tsIndex = lines.firstIndex(of: tsLine) else { continue }
            let textLines = lines[(tsIndex + 1)...].joined(separator: " ")
            let text = textLines.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            segments.append(SRTSegment(start: start, end: end, text: text))
        }
        return segments
    }

    /// "00:00:01,234" -> 1.234 giây
    private static func timestampToSeconds(_ ts: String) -> Double? {
        let clean = ts.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = clean.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}
