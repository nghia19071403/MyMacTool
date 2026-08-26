import Foundation
import AppKit

/// Dịch vụ lồng tiếng: SRT → giọng đọc (edge-tts) → ghép vào video (FFmpeg).
///
/// Quy trình:
/// 1. Parse file SRT lấy timestamp + text
/// 2. Dùng edge-tts (Python) tạo audio cho từng câu
/// 3. Dùng FFmpeg ghép các đoạn audio theo đúng timestamp
/// 4. Mix audio mới với video gốc → xuất video lồng tiếng
final class DubbingService {

    static let shared = DubbingService()
    private init() {}

    private let queue = DispatchQueue(label: "dubbing-service", qos: .userInitiated)

    // MARK: - Public API

    /// Bắt đầu lồng tiếng cho 1 task
    func start(_ task: DubbingTask) {
        task.status = .running
        updateStatus(task, progress: 0.0, message: "Đang chuẩn bị...")

        queue.async { [weak self] in
            guard let self else { return }
            self.execute(task)
        }
    }

    /// Hủy task đang chạy
    func cancel(_ task: DubbingTask) {
        task.process?.terminate()
        task.process = nil
        DispatchQueue.main.async {
            task.status = .idle
            task.statusMessage = "Đã hủy"
        }
    }

    // MARK: - Execute Pipeline

    private func execute(_ task: DubbingTask) {
        // 1. Kiểm tra Python + edge-tts
        updateStatus(task, progress: 0.02, message: "Đang kiểm tra Python...")
        guard let python = SystemEnvironment.shared.resolvePython() else {
            fail(task, message: "Không tìm thấy Python3.")
            return
        }

        updateStatus(task, progress: 0.05, message: "Đang kiểm tra edge-tts...")
        guard SystemEnvironment.shared.verifyEdgeTTS(python: python) else {
            fail(task, message: "Không tìm thấy edge-tts. Thử chạy: pip3 install edge-tts")
            return
        }

        updateStatus(task, progress: 0.08, message: "Đang kiểm tra FFmpeg...")
        guard let ffmpeg = SystemEnvironment.shared.resolveFFmpeg() else {
            fail(task, message: "Không tìm thấy FFmpeg.")
            return
        }

        // 2. Tạo thư mục tạm
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dubbing_\(task.id.uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 3. Chạy Python script: parse SRT → edge-tts → tạo audio từng segment → ghép thành 1 file audio
        updateStatus(task, progress: 0.10, message: "Đang tạo giọng đọc...")

        let outputDir = task.srtURL.deletingLastPathComponent()
        let baseName = task.srtURL.deletingPathExtension().lastPathComponent
        let outputPath = outputDir.appendingPathComponent("\(baseName)_dubbed.mp3").path

        let success = runDubbingScript(
            task: task,
            python: python,
            ffmpeg: ffmpeg,
            tempDir: tempDir,
            outputPath: outputPath
        )

        if success {
            DispatchQueue.main.async {
                task.progress = 1.0
                task.statusMessage = "Hoàn tất! File audio lồng tiếng đã được tạo."
                task.status = .done
                NSWorkspace.shared.open(outputDir)
            }
        }
    }

    // MARK: - Python Script

    private func runDubbingScript(
        task: DubbingTask,
        python: String,
        ffmpeg: String,
        tempDir: URL,
        outputPath: String
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)

        // Script Python: parse SRT → edge-tts từng segment → ghép thành 1 file audio
        let script = Self.buildPythonScript(
            srtPath: task.srtURL.path,
            videoPath: "",
            outputPath: outputPath,
            tempDir: tempDir.path,
            ffmpegPath: ffmpeg,
            voice: task.voice.voiceName,
            pitch: task.voice.pitch,
            rate: "+0%",
            keepOriginal: false,
            originalVolume: 0
        )

        process.arguments = ["-c", script]

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        let ffmpegDir = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path
        env["PATH"] = "\(ffmpegDir):/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
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

            // Đọc nốt data còn sót
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
                // Lấy dòng error cuối cùng để hiện cho user
                let lines = allOutput.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let lastLines = lines.suffix(3).joined(separator: " | ")
                let errMsg = lastLines.isEmpty ? "Exit code: \(process.terminationStatus)" : lastLines
                fail(task, message: "Lồng tiếng thất bại: \(String(errMsg.prefix(300)))")
                print("❌ Dubbing script full output:\n\(allOutput)")
                return false
            }
        } catch {
            fileHandle.readabilityHandler = nil
            task.process = nil
            fail(task, message: "Không thể chạy script: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Python Script Builder

    private static func buildPythonScript(
        srtPath: String,
        videoPath: String,
        outputPath: String,
        tempDir: String,
        ffmpegPath: String,
        voice: String,
        pitch: String,
        rate: String,
        keepOriginal: Bool,
        originalVolume: Double
    ) -> String {
        """
        import asyncio
        import os
        import re
        import subprocess
        import sys

        # --- Config ---
        SRT_PATH = r\"\"\"\(srtPath)\"\"\"
        OUTPUT_PATH = r\"\"\"\(outputPath)\"\"\"
        TEMP_DIR = r\"\"\"\(tempDir)\"\"\"
        FFMPEG = r\"\"\"\(ffmpegPath)\"\"\"
        VOICE = "\(voice)"
        PITCH = "\(pitch)"
        RATE = "\(rate)"

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
                ts_line = lines[1]
                match = re.match(r'(\\d{2}:\\d{2}:\\d{2}[,.]\\d{3})\\s*-->\\s*(\\d{2}:\\d{2}:\\d{2}[,.]\\d{3})', ts_line)
                if not match:
                    continue
                start_str = match.group(1).replace(',', '.')
                end_str = match.group(2).replace(',', '.')
                text = ' '.join(lines[2:]).strip()
                if text:
                    segments.append({'start': start_str, 'end': end_str, 'text': text})
            return segments

        def ts_to_seconds(ts):
            parts = ts.split(':')
            h, m = int(parts[0]), int(parts[1])
            s = float(parts[2])
            return h * 3600 + m * 60 + s

        # --- TTS ---
        async def generate_audio_segments(segments):
            import edge_tts
            total = len(segments)
            failed = 0
            for i, seg in enumerate(segments):
                out_file = os.path.join(TEMP_DIR, f"seg_{i:04d}.mp3")
                try:
                    communicate = edge_tts.Communicate(seg['text'], VOICE, rate=RATE, pitch=PITCH)
                    await communicate.save(out_file)
                except Exception as e:
                    failed += 1
                    print(f"[warn] TTS lỗi câu {i+1}: {str(e)[:80]}", flush=True)
                    # Tạo 1s silence thay thế
                    subprocess.run([
                        FFMPEG, '-y', '-f', 'lavfi', '-i',
                        'anullsrc=r=44100:cl=mono', '-t', '1',
                        '-q:a', '2', out_file
                    ], capture_output=True)
                seg['audio_file'] = out_file
                progress = int((i + 1) / total * 80)
                print(f"[progress] {progress}%", flush=True)
                if (i + 1) % 10 == 0:
                    print(f"[tts] {i+1}/{total} câu (lỗi: {failed})", flush=True)

        # --- Build full audio with silence padding theo timestamp ---
        def build_full_audio(segments):
            \"\"\"Ghép các segment audio theo đúng timestamp SRT → 1 file MP3.\"\"\"
            if not segments:
                print("[error] Không có segment nào!", flush=True)
                sys.exit(1)

            # Tính tổng duration từ segment cuối
            last_end = ts_to_seconds(segments[-1]['end'])
            duration = last_end + 1  # thêm 1s buffer

            # Tạo file silence nền
            silent_path = os.path.join(TEMP_DIR, "silent.mp3")
            subprocess.run([
                FFMPEG, '-y', '-f', 'lavfi', '-i',
                f'anullsrc=r=44100:cl=mono',
                '-t', str(duration),
                '-q:a', '2', silent_path
            ], capture_output=True)

            # Filter complex: overlay từng segment vào đúng vị trí
            inputs = ['-i', silent_path]
            filter_parts = []

            for i, seg in enumerate(segments):
                audio_file = seg.get('audio_file')
                if not audio_file or not os.path.exists(audio_file):
                    continue
                inputs.extend(['-i', audio_file])
                start_sec = ts_to_seconds(seg['start'])
                filter_parts.append(f"[{i+1}]adelay={int(start_sec*1000)}|{int(start_sec*1000)}[d{i}]")

            if not filter_parts:
                # Fallback: concat đơn giản
                return build_simple_concat(segments)

            mix_inputs = "[0]" + "".join(f"[d{i}]" for i in range(len(filter_parts)))
            filter_str = ";".join(filter_parts) + f";{mix_inputs}amix=inputs={len(filter_parts)+1}:duration=first[out]"

            cmd = [FFMPEG, '-y'] + inputs + [
                '-filter_complex', filter_str,
                '-map', '[out]',
                '-ac', '1', '-ar', '44100',
                OUTPUT_PATH
            ]

            print("[progress] 85%", flush=True)
            print("[build] Đang ghép audio theo timestamp...", flush=True)

            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"[warn] FFmpeg mix lỗi, dùng concat fallback: {result.stderr[:200]}", flush=True)
                return build_simple_concat(segments)

            return OUTPUT_PATH

        def build_simple_concat(segments):
            \"\"\"Fallback: nối các audio segment liên tiếp.\"\"\"
            list_path = os.path.join(TEMP_DIR, "concat_list.txt")
            with open(list_path, 'w') as f:
                for seg in segments:
                    audio_file = seg.get('audio_file')
                    if audio_file and os.path.exists(audio_file):
                        f.write(f"file '{audio_file}'\\n")

            subprocess.run([
                FFMPEG, '-y', '-f', 'concat', '-safe', '0',
                '-i', list_path, '-c', 'copy', OUTPUT_PATH
            ], capture_output=True)
            return OUTPUT_PATH

        # --- Main ---
        async def main():
            print("[progress] 10%", flush=True)
            print("[parse] Đang đọc file SRT...", flush=True)

            segments = parse_srt(SRT_PATH)
            if not segments:
                print("[error] File SRT rỗng hoặc không hợp lệ!", flush=True)
                sys.exit(1)

            print(f"[info] Tìm thấy {len(segments)} câu trong SRT", flush=True)
            print("[progress] 12%", flush=True)

            # TTS
            await generate_audio_segments(segments)

            print("[progress] 82%", flush=True)

            # Ghép thành 1 file audio
            build_full_audio(segments)

            print("[progress] 100%", flush=True)
            print("Done!", flush=True)

        asyncio.run(main())
        """
    }

    // MARK: - Output Handling

    private func handleOutput(task: DubbingTask, output: String) {
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains("[progress]") {
                if let match = trimmed.range(of: #"\d+"#, options: .regularExpression) {
                    let percent = Double(trimmed[match]) ?? 0
                    let appProgress = 0.10 + (percent / 100.0) * 0.90
                    task.progress = min(max(appProgress, 0.10), 1.0)
                }
            }

            if trimmed.contains("[tts]") {
                let msg = trimmed.replacingOccurrences(of: "[tts] ", with: "")
                task.statusMessage = "Đang tạo giọng đọc: \(msg)"
            } else if trimmed.contains("[build]") || trimmed.contains("[merge]") {
                let msg = trimmed
                    .replacingOccurrences(of: "[build] ", with: "")
                    .replacingOccurrences(of: "[merge] ", with: "")
                task.statusMessage = msg
            } else if trimmed.contains("[error]") {
                let msg = trimmed.replacingOccurrences(of: "[error] ", with: "")
                task.statusMessage = "Lỗi: \(msg)"
            } else if trimmed.contains("[warn]") {
                let msg = trimmed.replacingOccurrences(of: "[warn] ", with: "")
                task.statusMessage = "⚠️ \(msg)"
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
        }
    }
}
