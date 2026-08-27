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

    /// Đưa task vào hàng đợi. Vì `queue` là serial nên các task chạy tuần tự,
    /// mỗi lần chỉ 1 task chạy VieNeu (rất nặng RAM/CPU).
    func enqueue(_ task: DubbingTask) {
        DispatchQueue.main.async {
            task.status = .queued
            task.progress = 0
            task.statusMessage = "Đang chờ trong hàng đợi..."
        }
        queue.async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                task.status = .running
                task.statusMessage = "Đang chuẩn bị..."
            }
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
        // Kiểm tra file SRT tồn tại trước khi chạy
        guard FileManager.default.fileExists(atPath: task.srtURL.path) else {
            fail(task, message: "Không tìm thấy file SRT: \(task.srtURL.lastPathComponent)")
            return
        }

        updateStatus(task, progress: 0.02, message: "Đang kiểm tra Python...")
        updateStatus(task, progress: 0.05, message: "Đang kiểm tra VieNeu-TTS...")
        guard let python = SystemEnvironment.shared.resolveVieNeuPython() else {
            fail(task, message: "Không tìm thấy VieNeu-TTS (cần Python 3.10+). Thử: pip install vieneu")
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

        SR = 48000  # VieNeu-TTS sample rate

        # --- Parse timestamp "00:00:01,234" -> giây ---
        def ts_to_sec(ts):
            ts = ts.strip().replace(',', '.')
            parts = ts.split(':')
            h, m = int(parts[0]), int(parts[1])
            s = float(parts[2])
            return h * 3600 + m * 60 + s

        # --- Parse SRT: giữ start/end/text ---
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
                try:
                    start_str, end_str = [p.strip() for p in timestamp.split('-->')]
                    start = ts_to_sec(start_str)
                    end = ts_to_sec(end_str)
                except Exception:
                    continue
                text = ' '.join(lines[2:]).strip()
                if text:
                    segments.append({'start': start, 'end': end, 'text': text})
            return segments

        # --- Time-stretch audio cho vừa khung thời gian (giữ cao độ) ---
        def fit_to_duration(audio, target_len):
            cur = len(audio)
            if cur == 0 or target_len <= 0:
                return audio
            # Chỉ nén khi audio dài hơn khung (tránh nói tràn sang câu sau).
            # Nếu ngắn hơn thì để nguyên (phần còn lại là im lặng).
            if cur <= target_len:
                return audio
            rate = cur / target_len  # > 1 => tăng tốc
            try:
                import librosa
                stretched = librosa.effects.time_stretch(audio.astype(np.float32), rate=rate)
                return stretched
            except Exception:
                # Fallback: resample tuyến tính
                idx = np.linspace(0, cur - 1, target_len).astype(np.int64)
                return audio[idx]

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

        print("[progress] 15%", flush=True)
        print("[info] Đang tạo giọng đọc theo timestamp...", flush=True)

        # Tạo track im lặng dài bằng end câu cuối (+0.5s đệm)
        total_sec = max(seg['end'] for seg in segments) + 0.5
        timeline = np.zeros(int(total_sec * SR), dtype=np.float32)

        n = len(segments)
        empty_count = 0
        try:
            for i, seg in enumerate(segments):
                text = seg['text']
                if REF_AUDIO:
                    audio = vieneu.infer(text, ref_audio=REF_AUDIO)
                else:
                    audio = vieneu.infer(text, voice=VOICE)
                audio = np.asarray(audio, dtype=np.float32)

                # VieNeu chỉ đọc được tiếng Việt — text không đọc được sẽ ra rỗng
                if len(audio) == 0:
                    empty_count += 1
                    progress = 15 + int((i + 1) / n * 70)
                    print(f"[progress] {min(progress, 85)}%", flush=True)
                    continue

                # Nén cho vừa khung thời gian của câu (nếu bị tràn)
                target_len = int((seg['end'] - seg['start']) * SR)
                audio = fit_to_duration(audio, target_len)

                # Đặt vào đúng vị trí start trên timeline
                start_sample = int(seg['start'] * SR)
                end_sample = start_sample + len(audio)
                # Nới timeline nếu tràn cuối
                if end_sample > len(timeline):
                    timeline = np.concatenate([timeline, np.zeros(end_sample - len(timeline), dtype=np.float32)])
                # Mix (cộng dồn, phòng khi 2 câu chồng nhẹ)
                timeline[start_sample:end_sample] += audio

                progress = 15 + int((i + 1) / n * 70)
                print(f"[progress] {min(progress, 85)}%", flush=True)
                if (i + 1) % 5 == 0:
                    print(f"[info] Đã tạo {i+1}/{n} câu", flush=True)

            # Cảnh báo nếu quá nhiều câu không đọc được (SRT không phải tiếng Việt)
            if empty_count > n // 2:
                print(f"[error] {empty_count}/{n} câu không tạo được giọng. "
                      f"VieNeu-TTS chỉ đọc tiếng Việt — hãy lồng tiếng từ file SRT ĐÃ DỊCH (_vi.srt).", flush=True)
                sys.exit(2)

            # Chống clip: chuẩn hóa nếu vượt biên độ
            peak = float(np.max(np.abs(timeline))) if len(timeline) else 0.0
            if peak > 1.0:
                timeline = timeline / peak * 0.98

            print("[progress] 90%", flush=True)
            print("[info] Đang lưu file audio...", flush=True)
            vieneu.save(timeline, OUTPUT_PATH)
            print("[progress] 100%", flush=True)
            print("Done!", flush=True)
        except Exception as e:
            print(f"[error] VieNeu-TTS lỗi: {e}", flush=True)
            import traceback
            traceback.print_exc()
            sys.exit(1)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", script]

        process.environment = SystemEnvironment.pythonEnvironment(for: python)

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
