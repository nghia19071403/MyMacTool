import Foundation
import Combine
import AppKit

/// Điều phối chạy Whisper song song cho nhiều VideoTask,
/// giới hạn số lượng chạy đồng thời để không quá tải máy.
///
/// Whisper rất nặng (~2-4GB RAM + nhiều CPU mỗi instance).
/// Mặc định chạy tối đa 2 video cùng lúc — vừa nhanh vừa không lag.
final class TranscriptionService: ObservableObject {

    /// Số video Whisper chạy đồng thời (user có thể đổi trong UI)
    var maxConcurrent: Int = 2 {
        didSet { tryStartNext() }
    }

    private var runningCount = 0
    private var pending: [VideoTask] = []
    private let envQueue = DispatchQueue(label: "env-check", qos: .userInitiated)

    // MARK: - Public API

    /// Đưa 1 task vào hàng đợi
    func enqueue(_ task: VideoTask) {
        guard task.status == .idle || task.status.isError || task.status == .done else { return }

        task.status = .queued
        task.statusMessage = "Đang chờ trong hàng đợi..."
        task.progress = 0
        pending.append(task)
        tryStartNext()
    }

    /// Đưa tất cả task vào hàng đợi
    func enqueueAll(_ tasks: [VideoTask]) {
        for task in tasks { enqueue(task) }
    }

    /// Hủy 1 task
    func cancel(_ task: VideoTask) {
        pending.removeAll { $0.id == task.id }
        if task.status == .running { task.process?.terminate() }
        task.status = .idle
        task.statusMessage = "Đã hủy"
    }

    // MARK: - Queue Engine

    private func tryStartNext() {
        while runningCount < maxConcurrent, !pending.isEmpty {
            let task = pending.removeFirst()
            runningCount += 1
            start(task)
        }
    }

    private func taskFinished() {
        runningCount = max(0, runningCount - 1)
        tryStartNext()
    }

    // MARK: - Start Task

    private func start(_ task: VideoTask) {
        task.status = .running
        updateStatus(task, progress: 0.0, message: "Đang chuẩn bị...")

        envQueue.async { [weak self] in
            guard let self else { return }

            self.updateStatus(task, progress: 0.05, message: "Đang kiểm tra Python...")
            guard let python = SystemEnvironment.shared.resolvePython() else {
                self.fail(task, message: "Không tìm thấy Python3.")
                return
            }

            self.updateStatus(task, progress: 0.10, message: "Đang kiểm tra FFmpeg...")
            guard let ffmpeg = SystemEnvironment.shared.resolveFFmpeg() else {
                self.fail(task, message: "Không tìm thấy FFmpeg.")
                return
            }

            self.updateStatus(task, progress: 0.15, message: "Đang kiểm tra faster-whisper...")
            guard SystemEnvironment.shared.ensureFasterWhisper(python: python, onStatus: { msg in
                self.updateStatus(task, progress: 0.15, message: msg)
            }) else {
                self.fail(task, message: "Không thể cài faster-whisper. Thử chạy: pip3 install faster-whisper")
                return
            }

            DispatchQueue.main.async {
                self.runWhisperProcess(task: task, python: python, ffmpeg: ffmpeg)
            }
        }
    }

    // MARK: - Run faster-whisper

    private func runWhisperProcess(task: VideoTask, python: String, ffmpeg: String) {
        let outputDirectory = task.url.deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)

        // Script Python inline chạy faster-whisper, xuất file SRT
        let script = """
        import sys
        from faster_whisper import WhisperModel

        input_file = sys.argv[1]
        output_dir = sys.argv[2]
        model_size = sys.argv[3]

        import os
        base_name = os.path.splitext(os.path.basename(input_file))[0]
        srt_path = os.path.join(output_dir, base_name + ".srt")

        print("Loading model...", flush=True)
        model = WhisperModel(model_size, device="cpu", compute_type="int8")

        print("Transcribing...", flush=True)
        segments, info = model.transcribe(input_file, language="zh", beam_size=5)

        print(f"Detected language: {info.language} (prob={info.language_probability:.2f})", flush=True)

        def format_timestamp(seconds):
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            secs = int(seconds % 60)
            millis = int((seconds - int(seconds)) * 1000)
            return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"

        with open(srt_path, "w", encoding="utf-8") as f:
            for i, segment in enumerate(segments, start=1):
                start_ts = format_timestamp(segment.start)
                end_ts = format_timestamp(segment.end)
                f.write(f"{i}\\n")
                f.write(f"{start_ts} --> {end_ts}\\n")
                f.write(f"{segment.text.strip()}\\n\\n")

                progress = min(int((segment.end / max(info.duration, 1)) * 100), 100)
                print(f"[progress] {progress}%", flush=True)

        print("Done!", flush=True)
        """

        process.arguments = ["-c", script, task.url.path, outputDirectory.path, "small"]

        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        let ffmpegDir = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path
        environment["PATH"] = "\(ffmpegDir):\(currentPath)"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        task.process = process
        task.pipe = pipe

        let fileHandle = pipe.fileHandleForReading
        var didFinish = false

        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.handleOutput(task: task, output: output) }
        }

        process.terminationHandler = { [weak self] finishedProcess in
            guard !didFinish else { return }
            didFinish = true
            fileHandle.readabilityHandler = nil

            let remainingData = fileHandle.readDataToEndOfFile()
            if !remainingData.isEmpty, let text = String(data: remainingData, encoding: .utf8) {
                DispatchQueue.main.async { self?.handleOutput(task: task, output: text) }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                task.process = nil
                task.pipe = nil

                if finishedProcess.terminationStatus == 0 {
                    self.handleWhisperSuccess(task: task, outputDirectory: outputDirectory)
                } else {
                    self.fail(task, message: "faster-whisper thất bại. Exit code: \(finishedProcess.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
            updateStatus(task, progress: 0.20, message: "Đang tải model faster-whisper...")
        } catch {
            fileHandle.readabilityHandler = nil
            task.process = nil
            task.pipe = nil
            fail(task, message: "Không thể chạy faster-whisper: \(error.localizedDescription)")
        }
    }

    // MARK: - Whisper Success → Dịch (nếu cần)

    private func handleWhisperSuccess(task: VideoTask, outputDirectory: URL) {
        updateStatus(task, progress: 0.90, message: "Đang tìm file SRT...")

        let videoName = task.url.deletingPathExtension().lastPathComponent
        let srtURL = outputDirectory.appendingPathComponent("\(videoName).srt")
        let srtOption = task.srtOutputOption

        guard FileManager.default.fileExists(atPath: srtURL.path) else {
            task.progress = 1.0
            task.statusMessage = "Hoàn tất! File SRT đã được tạo."
            task.status = .done
            openOutputFolder(outputDirectory)
            taskFinished()
            return
        }

        // Nếu cần dịch sang tiếng Việt
        if srtOption.needsTranslation {
            updateStatus(task, progress: 0.92, message: "Đang dịch phụ đề sang tiếng Việt...")

            SRTTranslator.shared.translate(
                srtURL: srtURL,
                onProgress: { [weak self] progress, message in
                    let appProgress = 0.92 + progress * 0.07
                    self?.updateStatus(task, progress: appProgress, message: message)
                },
                completion: { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }

                        // Nếu chỉ cần bản dịch → xóa file gốc
                        if !srtOption.keepOriginal {
                            try? FileManager.default.removeItem(at: srtURL)
                        }

                        switch result {
                        case .success:
                            let msg = srtOption == .both
                                ? "Hoàn tất! File SRT gốc + bản dịch tiếng Việt đã được tạo."
                                : "Hoàn tất! File phụ đề tiếng Việt đã được tạo."
                            task.progress = 1.0
                            task.statusMessage = msg
                            task.status = .done

                        case .failure(let error):
                            task.progress = 1.0
                            task.statusMessage = "SRT đã tạo. Dịch lỗi: \(error.localizedDescription)"
                            task.status = .done
                        }

                        self.openOutputFolder(outputDirectory)
                        self.taskFinished()
                    }
                }
            )
        } else {
            // Chỉ cần file gốc
            task.progress = 1.0
            task.statusMessage = "Hoàn tất! File SRT gốc đã được tạo."
            task.status = .done
            openOutputFolder(outputDirectory)
            taskFinished()
        }
    }

    // MARK: - Output Parsing

    private static let percentRegex = try! NSRegularExpression(pattern: #"(\d{1,3})%"#)

    private func handleOutput(task: VideoTask, output: String) {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = Self.percentRegex.matches(in: output, range: range)

        guard let match = matches.last, match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: output),
              let whisperPercent = Double(output[swiftRange]) else {
            updateStatusFromText(task, text: output)
            return
        }

        let appProgress = 0.20 + (whisperPercent / 100.0) * 0.70
        updateStatus(task, progress: min(max(appProgress, 0.20), 0.90), message: "Đang nhận dạng video... \(Int(whisperPercent))%")
    }

    private func updateStatusFromText(_ task: VideoTask, text: String) {
        let lower = text.lowercased()
        if lower.contains("loading model") || lower.contains("load") {
            updateStatus(task, progress: 0.20, message: "Đang tải model faster-whisper...")
        } else if lower.contains("detect") {
            updateStatus(task, progress: 0.22, message: "Đang nhận diện ngôn ngữ...")
        } else if lower.contains("transcrib") {
            updateStatus(task, progress: 0.25, message: "Đang nhận dạng giọng nói...")
        } else if lower.contains("done") {
            updateStatus(task, progress: 0.90, message: "Đang ghi file SRT...")
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ task: VideoTask, progress: Double, message: String) {
        DispatchQueue.main.async {
            task.progress = min(max(progress, 0), 1)
            task.statusMessage = message
        }
    }

    private func fail(_ task: VideoTask, message: String) {
        DispatchQueue.main.async {
            task.status = .error(message)
            task.statusMessage = "Lỗi: \(message)"
            task.process = nil
            task.pipe = nil
            self.taskFinished()
        }
    }

    private func openOutputFolder(_ folderURL: URL) {
        NSWorkspace.shared.open(folderURL)
    }
}
