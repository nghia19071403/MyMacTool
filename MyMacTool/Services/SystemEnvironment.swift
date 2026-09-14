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

    private var _vieneuPython: String?

    /// Tìm Python có VieNeu-TTS (clone giọng). Ưu tiên venv chuyên dụng vì
    /// vieneu yêu cầu Python >= 3.10 (system python thường là 3.9).
    /// Trả về nil nếu chưa có Python 3.10+ với vieneu.
    func resolveVieNeuPython() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = _vieneuPython { return cached }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Ưu tiên venv chuyên dụng của app
        let candidates = [
            "\(home)/.mymactool-venv/bin/python3",
            "\(home)/.mymactool-venv/bin/python",
            "\(home)/whisper-env/bin/python3",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.10",
            "/opt/homebrew/bin/python3"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if Self.checkVieNeuInstalled(pythonPath: path) {
                print("✅ Found VieNeu python:", path)
                _vieneuPython = path
                return path
            }
        }
        print("❌ VieNeu python not found")
        return nil
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
        process.environment = Self.pythonEnvironment(for: python)
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
        process.environment = Self.pythonEnvironment(for: pythonPath)
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
        process.environment = Self.pythonEnvironment(for: pythonPath)
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
        process.environment = Self.pythonEnvironment(for: pythonPath)
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
        process.environment = Self.pythonEnvironment(for: pythonPath)
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
        process.environment = Self.pythonEnvironment(for: pythonPath)

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
        process.environment = Self.pythonEnvironment(for: pythonPath)

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
    /// Environment cho subprocess Python.
    ///
    /// QUAN TRỌNG: KHÔNG bao giờ set PYTHONPATH tới site-packages của phiên bản
    /// Python khác — làm vậy sẽ khiến venv 3.12 nạp numpy/onnxruntime build cho
    /// 3.9 và crash ("Error importing numpy..."). Mỗi interpreter (system python
    /// hay venv) tự biết site-packages của chính nó qua sys.prefix / pyvenv.cfg.
    ///
    /// Ở đây chỉ mở rộng PATH (để tìm binary như ffmpeg) và đảm bảo HOME có mặt.
    static func pythonEnvironment(for pythonPath: String? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Mở rộng PATH — chỉ để tìm binary phụ trợ (ffmpeg, ...), không ảnh hưởng import
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        var extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin"
        ]
        // Nếu biết python cụ thể, đưa thư mục bin của nó lên đầu PATH
        if let pythonPath {
            let binDir = (pythonPath as NSString).deletingLastPathComponent
            extraPaths.insert(binDir, at: 0)
        }
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

        // Xóa PYTHONPATH kế thừa để tránh nạp nhầm site-packages cross-version
        env.removeValue(forKey: "PYTHONPATH")

        // Đảm bảo HOME được set (sandbox có thể thiếu)
        if env["HOME"] == nil {
            env["HOME"] = home
        }

        return env
    }

    // MARK: - CPU Info

    private var _cpuInfo: CPUInfo?

    /// Đọc thông tin CPU của máy đang chạy (số nhân, P-core/E-core, tên chip).
    /// Kết quả được cache. Dùng để tự chọn số luồng phù hợp trên mọi máy.
    func cpuInfo() -> CPUInfo {
        lock.lock(); defer { lock.unlock() }
        if let cached = _cpuInfo { return cached }
        let info = Self.readCPUInfo()
        _cpuInfo = info
        return info
    }

    private static func readCPUInfo() -> CPUInfo {
        func sysctlInt(_ name: String) -> Int? {
            var value: Int = 0
            var size = MemoryLayout<Int>.size
            let result = sysctlbyname(name, &value, &size, nil, 0)
            return result == 0 ? value : nil
        }

        func sysctlString(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
            return String(cString: buffer)
        }

        // Tổng nhân logic (bao gồm hyper-threading trên Intel)
        let logical = sysctlInt("hw.logicalcpu")
            ?? ProcessInfo.processInfo.activeProcessorCount
        // Nhân vật lý
        let physical = sysctlInt("hw.physicalcpu") ?? logical
        // P-core / E-core (chỉ Apple Silicon mới có perflevel)
        let pCores = sysctlInt("hw.perflevel0.physicalcpu")
        let eCores = sysctlInt("hw.perflevel1.physicalcpu")
        // Tên chip
        let brand = sysctlString("machdep.cpu.brand_string")
            ?? sysctlString("hw.model")
            ?? "Unknown CPU"

        return CPUInfo(
            brand: brand,
            logicalCores: logical,
            physicalCores: physical,
            performanceCores: pCores,
            efficiencyCores: eCores
        )
    }
}

// MARK: - CPUInfo

/// Thông tin CPU của máy đang chạy.
struct CPUInfo {
    let brand: String            // VD "Apple M2" / "Intel(R) Core(TM) i7..."
    let logicalCores: Int        // tổng luồng logic
    let physicalCores: Int       // nhân vật lý
    let performanceCores: Int?   // P-core (nil nếu không phải Apple Silicon)
    let efficiencyCores: Int?    // E-core (nil nếu không phải Apple Silicon)

    /// Có phải Apple Silicon (có phân P-core/E-core) không.
    var isAppleSilicon: Bool { performanceCores != nil }

    /// Số luồng "khuyến nghị" để chạy tác vụ nặng mà không nuốt hết máy.
    /// Apple Silicon: ưu tiên số P-core (nhanh, không đụng E-core lo việc nền).
    /// Còn lại: ~3/4 số nhân logic.
    var recommendedThreads: Int {
        if let p = performanceCores, p > 0 {
            return p
        }
        return Swift.max(2, logicalCores * 3 / 4)
    }

    /// Mô tả gọn để hiển thị cho người dùng.
    var summary: String {
        if let p = performanceCores, let e = efficiencyCores {
            return "\(brand) · \(logicalCores) nhân (\(p)P + \(e)E)"
        }
        return "\(brand) · \(logicalCores) nhân"
    }
}
