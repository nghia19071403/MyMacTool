import Foundation

/// Dò tìm và cache đường dẫn Python, FFmpeg, Whisper, yt-dlp.
/// Dùng chung cho toàn app, chỉ dò 1 lần.
final class SystemEnvironment {

    static let shared = SystemEnvironment()
    private init() {}

    private let lock = NSLock()
    private var _python: String?
    private var _ffmpeg: String?
    private var _whisperVerified = false
    private var _ytdlp: YtDlpMethod?

    // MARK: - Public API

    func resolvePython() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = _python { return cached }
        let found = Self.searchPython()
        _python = found
        return found
    }

    /// Reset cache — dùng khi cần re-detect (ví dụ sau khi cài package mới)
    func resetCache() {
        lock.lock(); defer { lock.unlock() }
        _python = nil
        _ffmpeg = nil
        _whisperVerified = false
    }

    func resolveFFmpeg() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = _ffmpeg { return cached }
        let found = Self.searchFFmpeg()
        _ffmpeg = found
        return found
    }

    func verifyWhisper(python: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if _whisperVerified { return true }
        let ok = Self.checkWhisperInstalled(pythonPath: python)
        if ok { _whisperVerified = true }
        return ok
    }

    /// Kiểm tra faster-whisper đã cài chưa. Nếu chưa → tự động cài.
    /// Trả về true nếu đã sẵn sàng sử dụng.
    func ensureFasterWhisper(python: String, onStatus: ((String) -> Void)? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if _whisperVerified { return true }

        // Kiểm tra đã cài chưa
        if Self.checkFasterWhisperInstalled(pythonPath: python) {
            _whisperVerified = true
            return true
        }

        // Chưa có → tự động cài
        onStatus?("Đang cài đặt faster-whisper...")
        print("📦 faster-whisper chưa có, đang cài...")

        let installed = Self.installFasterWhisper(pythonPath: python)
        if installed {
            _whisperVerified = true
            print("✅ Cài faster-whisper thành công!")
        } else {
            print("❌ Cài faster-whisper thất bại")
        }
        return installed
    }

    /// Kiểm tra openai-whisper (module whisper) đã cài chưa. Nếu chưa → tự động cài.
    /// Trả về true nếu đã sẵn sàng sử dụng.
    func ensureWhisper(python: String, onStatus: ((String) -> Void)? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if _whisperVerified { return true }

        // Kiểm tra đã cài chưa
        if Self.checkWhisperInstalled(pythonPath: python) {
            _whisperVerified = true
            return true
        }

        // Chưa có → tự động cài
        onStatus?("Đang cài đặt openai-whisper...")
        print("📦 openai-whisper chưa có, đang cài...")

        let installed = Self.installWhisper(pythonPath: python)
        if installed {
            _whisperVerified = true
            print("✅ Cài openai-whisper thành công!")
        } else {
            print("❌ Cài openai-whisper thất bại")
        }
        return installed
    }

    /// Kiểm tra edge-tts đã cài trong Python env chưa.
    func verifyEdgeTTS(python: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Self.checkEdgeTTSInstalled(pythonPath: python)
    }

    /// Kiểm tra VieNeu-TTS đã cài trong Python env chưa.
    func verifyVieNeuTTS(python: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Self.checkVieNeuInstalled(pythonPath: python)
    }

    func resolveYtDlp(python: String?) -> YtDlpMethod? {
        lock.lock(); defer { lock.unlock() }
        if let cached = _ytdlp { return cached }

        if let bin = Self.searchYtDlpBinary() {
            _ytdlp = .binary(bin)
            return _ytdlp
        }

        if let python, Self.checkYtDlpModule(python: python) {
            _ytdlp = .pythonModule(python: python)
            return _ytdlp
        }

        return nil
    }

    // MARK: - Private Helpers

    private static func searchPython() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Ưu tiên whisper-env (chứa tất cả package) trước system python
        let whisperEnvPython = "\(home)/whisper-env/bin/python3"
        if FileManager.default.isExecutableFile(atPath: whisperEnvPython) {
            print("✅ Found Python (whisper-env):", whisperEnvPython)
            return whisperEnvPython
        }

        let paths = [
            "\(home)/whisper/venv/bin/python3",
            "\(home)/.venv/bin/python3",
            "\(home)/venv/bin/python3",
            "\(home)/miniconda3/bin/python3",
            "\(home)/anaconda3/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "\(home)/Library/Python/3.9/bin/python3",
            "\(home)/Library/Python/3.10/bin/python3",
            "\(home)/Library/Python/3.11/bin/python3",
            "\(home)/Library/Python/3.12/bin/python3",
            "\(home)/Library/Python/3.13/bin/python3"
        ]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            print("✅ Found Python:", path)
            return path
        }
        print("❌ Python3 not found")
        return nil
    }

    private static func searchFFmpeg() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            "\(home)/.local/bin/ffmpeg"
        ]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            print("✅ Found FFmpeg:", path)
            return path
        }
        print("❌ FFmpeg not found")
        return nil
    }

    private static func searchYtDlpBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            "\(home)/.local/bin/yt-dlp"
        ]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            print("✅ Found yt-dlp binary:", path)
            return path
        }
        return nil
    }

    private static func checkYtDlpModule(python: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-m", "yt_dlp", "--version"]
        process.environment = Self.pythonEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            if ok { print("✅ Found yt-dlp qua python module") }
            return ok
        } catch {
            return false
        }
    }

    private static func checkWhisperInstalled(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "whisper", "--help"]
        process.environment = Self.pythonEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("❌ Whisper check error:", error)
            return false
        }
    }

    private static func checkFasterWhisperInstalled(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import faster_whisper; print('ok')"]
        process.environment = Self.pythonEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            if ok { print("✅ Found faster-whisper") }
            return ok
        } catch {
            print("❌ faster-whisper check error:", error)
            return false
        }
    }

    private static func checkEdgeTTSInstalled(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import edge_tts; print('ok')"]
        process.environment = Self.pythonEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            if ok { print("✅ Found edge-tts") }
            return ok
        } catch {
            print("❌ edge-tts check error:", error)
            return false
        }
    }

    private static func checkVieNeuInstalled(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import vieneu; print('ok')"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            if ok { print("✅ Found VieNeu-TTS") }
            return ok
        } catch {
            print("❌ VieNeu-TTS check error:", error)
            return false
        }
    }

    /// Tự động cài faster-whisper bằng pip
    private static func installFasterWhisper(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "pip", "install", "faster-whisper"]
        process.environment = Self.pythonEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            print("pip install faster-whisper output:\n\(output)")

            return process.terminationStatus == 0
        } catch {
            print("❌ pip install faster-whisper error:", error)
            return false
        }
    }

    /// Tự động cài openai-whisper bằng pip
    private static func installWhisper(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "pip", "install", "openai-whisper"]
        process.environment = Self.pythonEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            print("pip install openai-whisper output:\n\(output)")

            return process.terminationStatus == 0
        } catch {
            print("❌ pip install openai-whisper error:", error)
            return false
        }
    }

    // MARK: - Environment Helper

    /// Trả về environment dict đầy đủ PATH + PYTHONPATH cho subprocess.
    /// Đảm bảo user site-packages và Homebrew paths luôn có mặt,
    /// kể cả khi app chạy từ Xcode/Launchpad với PATH tối giản.
    static func pythonEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Mở rộng PATH
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let extraPaths = [
            "\(home)/whisper-env/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/Library/Python/3.9/bin",
            "\(home)/Library/Python/3.10/bin",
            "\(home)/Library/Python/3.11/bin",
            "\(home)/Library/Python/3.12/bin",
            "\(home)/Library/Python/3.13/bin",
            "\(home)/.local/bin"
        ]
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

        // Đảm bảo Python thấy user site-packages
        let userSitePackages = [
            "\(home)/whisper-env/lib/python3.14/site-packages",
            "\(home)/whisper-env/lib/python3.13/site-packages",
            "\(home)/whisper-env/lib/python3.12/site-packages",
            "\(home)/whisper-env/lib/python3.11/site-packages",
            "\(home)/Library/Python/3.9/lib/python/site-packages",
            "\(home)/Library/Python/3.10/lib/python/site-packages",
            "\(home)/Library/Python/3.11/lib/python/site-packages",
            "\(home)/Library/Python/3.12/lib/python/site-packages",
            "\(home)/Library/Python/3.13/lib/python/site-packages"
        ].filter { FileManager.default.fileExists(atPath: $0) }

        if !userSitePackages.isEmpty {
            let existing = env["PYTHONPATH"] ?? ""
            let allPaths = userSitePackages + (existing.isEmpty ? [] : [existing])
            env["PYTHONPATH"] = allPaths.joined(separator: ":")
        }

        // Đảm bảo HOME được set (sandbox có thể thiếu)
        if env["HOME"] == nil {
            env["HOME"] = home
        }

        // Không disable user site-packages
        env["PYTHONNOUSERSITE"] = nil

        return env
    }
}
