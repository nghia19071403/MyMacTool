import Foundation
import AppKit

/// Dịch vụ lồng tiếng: SRT → giọng đọc VieNeu-TTS (48kHz, offline) → file audio WAV.
///
/// Quy trình:
/// 1. Parse file SRT lấy text từng câu
/// 2. Dùng VieNeu-TTS (Python SDK) tạo audio cho toàn bộ text
/// 3. Xuất file WAV 48kHz
final class DubbingService {

    static let shared = DubbingService()
    private init() {}

    private let queue = DispatchQueue(label: "dubbing-service", qos: .userInitiated)

    /// Callback khi task hoàn tất (success/fail) — dùng để lưu history
    var onTaskCompleted: ((DubbingTask, Bool, String?) -> Void)?

    // MARK: - Public API

    func start(_ task: DubbingTask) {
        task.status = .running
        updateStatus(task, progress: 0.0, message: "Đang chuẩn bị...")

        queue.async { [weak self] in
            guard let self else { return }
            self.execute(task)
        }
    }

    func cancel(_ task: DubbingTask) {
        task.process?.terminate()
        task.process = nil
        DispatchQueue.main.async {
            task.status = .idle
            task.statusMessage = "Đã hủy"
        }
    }

    // MARK: - Execute

    private func execute(_ task: DubbingTask) {
        updateStatus(task, progress: 0.02, message: "Đang kiểm tra Python...")
        guard let python = SystemEnvironment.shared.resolvePython() else {
            fail(task, message: "Không tìm thấy Python3.")
            return
        }

        updateStatus(task, progress: 0.05, message: "Đang kiểm tra VieNeu-TTS...")
        guard SystemEnvironment.shared.verifyVieNeuTTS(python: python) else {
            fail(task, message: "Không tìm thấy VieNeu-TTS. Thử: pip install vieneu")
            return
        }

        updateStatus(task, progress: 0.10, message: "Đang tạo giọng đọc VieNeu...")

        let outputDir = task.srtURL.deletingLastPathComponent()
        let baseName = task.srtURL.deletingPathExtension().lastPathComponent
        let outputPath = outputDir.appendingPathComponent("\(baseName)_dubbed.wav").path

        let success = runVieNeuScript(task: task, python: python, outputPath: outputPath)

        if success {
            DispatchQueue.main.async {
                task.progress = 1.0
                task.statusMessage = "Hoàn tất! File audio đã được tạo."
                task.status = .done
                self.onTaskCompleted?(task, true, outputPath)
                NSWorkspace.shared.open(outputDir)
            }
        }
    }

    // MARK: - Python Script

    private func runVieNeuScript(task: DubbingTask, python: String, outputPath: String) -> Bool {
        let script = """
        import sys
        import re
        import numpy as np

        SRT_PATH = r\"\"\"\(task.srtURL.path)\"\"\"
        OUTPUT_PATH = r\"\"\"\(outputPath)\"\"\"
        VOICE = "\(task.voice.voiceName)"
        REF_AUDIO = r\"\"\"\(task.clonedVoiceRef?.path ?? "")\"\"\"

        # --- Parse SRT ---
        def parse_srt(path):
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            blocks = content.strip().split('\\n\\n')
            segments = []
            for block in blocks:
                lines = block.strip().split('\\n')
                if len(lines) < 3:
                    continue
                timestamp = lines[1].strip()
                if '-->' not in timestamp:
                    continue
                text = ' '.join(lines[2:]).strip()
                if text:
                    segments.append(text)
            return segments

        # --- Main ---
        print("[progress] 5%", flush=True)
        print("[info] Đang đọc file SRT...", flush=True)

        segments = parse_srt(SRT_PATH)
        if not segments:
            print("[error] File SRT rỗng!", flush=True)
            sys.exit(1)

        print(f"[info] Tìm thấy {len(segments)} câu", flush=True)
        print("[progress] 10%", flush=True)
        print(f"[info] Đang tải VieNeu-TTS...", flush=True)

        from vieneu import Vieneu
        vieneu = Vieneu()

        print("[progress] 20%", flush=True)
        print("[info] Đang tạo giọng đọc...", flush=True)

        # Ghép text thành 1 đoạn dài, VieNeu tự xử lý chunking
        full_text = '. '.join(segments)

        try:
            if REF_AUDIO:
                # Dùng giọng clone
                print(f"[info] Sử dụng giọng clone: {REF_AUDIO.split('/')[-1]}", flush=True)
                audio = vieneu.infer(full_text, ref_audio=REF_AUDIO)
            else:
                # Dùng giọng preset
                print(f"[info] Sử dụng giọng: {VOICE}", flush=True)
                audio = vieneu.infer(full_text, voice=VOICE)
            print("[progress] 85%", flush=True)
            print("[info] Đang lưu file audio...", flush=True)
            vieneu.save(audio, OUTPUT_PATH)
            print("[progress] 100%", flush=True)
            print("Done!", flush=True)
        except Exception as e:
            print(f"[error] VieNeu-TTS lỗi: {e}", flush=True)
            sys.exit(1)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", script]

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        task.process = process

        let fileHandle = pipe.fileHandleForReading
        var allOutput = ""
        let outputLock = NSLock()

        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            outputLock.lock()
            allOutput += output
            outputLock.unlock()
            DispatchQueue.main.async {
                self?.handleOutput(task: task, output: output)
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            fileHandle.readabilityHandler = nil

            let remaining = fileHandle.readDataToEndOfFile()
            if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                outputLock.lock()
                allOutput += text
                outputLock.unlock()
            }

            task.process = nil

            if process.terminationStatus == 0 {
                return true
            } else {
                let lines = allOutput.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let lastLines = lines.suffix(3).joined(separator: " | ")
                let errMsg = lastLines.isEmpty ? "Exit code: \(process.terminationStatus)" : lastLines
                fail(task, message: "Lồng tiếng thất bại: \(String(errMsg.prefix(300)))")
                return false
            }
        } catch {
            fileHandle.readabilityHandler = nil
            task.process = nil
            fail(task, message: "Không thể chạy script: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Output Handling

    private func handleOutput(task: DubbingTask, output: String) {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains("[progress]"),
               let match = trimmed.range(of: #"\d+"#, options: .regularExpression) {
                let percent = Double(trimmed[match]) ?? 0
                task.progress = min(max(percent / 100.0, 0), 1.0)
            } else if trimmed.contains("[info]") {
                let msg = trimmed.replacingOccurrences(of: "[info] ", with: "")
                task.statusMessage = msg
            } else if trimmed.contains("[error]") {
                let msg = trimmed.replacingOccurrences(of: "[error] ", with: "")
                task.statusMessage = "Lỗi: \(msg)"
            } else if trimmed.contains("Done!") {
                task.statusMessage = "Hoàn tất!"
            }
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ task: DubbingTask, progress: Double, message: String) {
        DispatchQueue.main.async {
            task.progress = min(max(progress, 0), 1)
            task.statusMessage = message
        }
    }

    private func fail(_ task: DubbingTask, message: String) {
        DispatchQueue.main.async {
            task.status = .error(message)
            task.statusMessage = "Lỗi: \(message)"
            task.process = nil
            self.onTaskCompleted?(task, false, nil)
        }
    }
}
