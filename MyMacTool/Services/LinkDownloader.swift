import Foundation

/// Tải video từ link (Bilibili...) bằng yt-dlp, báo tiến độ.
final class LinkDownloader {

    static let shared = LinkDownloader()
    private init() {}

    private static let percentRegex =
        try! NSRegularExpression(pattern: #"\[download\]\s+(\d{1,3}(?:\.\d+)?)%"#)

    func download(
        urlString: String,
        platformFolder: String,
        onProgress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.lowercased().hasPrefix("http") else {
            completion(.failure(SimpleError(message: "Link không hợp lệ.")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            onProgress(0.02, "Đang kiểm tra công cụ tải video...")

            let python = SystemEnvironment.shared.resolvePython()

            guard let ytdlp = SystemEnvironment.shared.resolveYtDlp(python: python) else {
                DispatchQueue.main.async {
                    completion(.failure(SimpleError(message: "Không tìm thấy yt-dlp. Cài bằng: pip3 install yt-dlp")))
                }
                return
            }

            let outputDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
                .appendingPathComponent(platformFolder)

            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let fileID = String(UUID().uuidString.prefix(8))
            let outputTemplate = outputDir.appendingPathComponent("\(fileID).%(ext)s").path

            let process = Process()
            var arguments = [trimmed, "-o", outputTemplate, "--no-playlist", "--newline"]

            switch ytdlp {
            case .binary(let path):
                process.executableURL = URL(fileURLWithPath: path)
            case .pythonModule(let pythonPath):
                process.executableURL = URL(fileURLWithPath: pythonPath)
                arguments = ["-m", "yt_dlp"] + arguments
            }

            if let ffmpeg = SystemEnvironment.shared.resolveFFmpeg() {
                let ffmpegDir = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path
                arguments += ["--ffmpeg-location", ffmpegDir]
            }

            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let fileHandle = pipe.fileHandleForReading
            var didFinish = false

            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                guard let text = String(data: data, encoding: .utf8) else { return }
                Self.parseProgress(text, onProgress: onProgress)
            }

            process.terminationHandler = { finished in
                guard !didFinish else { return }
                didFinish = true
                fileHandle.readabilityHandler = nil

                let remaining = fileHandle.readDataToEndOfFile()
                if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                    Self.parseProgress(text, onProgress: onProgress)
                }

                guard finished.terminationStatus == 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(SimpleError(message: "yt-dlp lỗi, exit code \(finished.terminationStatus)")))
                    }
                    return
                }

                let matched = (try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil))?
                    .filter { $0.lastPathComponent.hasPrefix(fileID) }
                    .filter { !["part", "ytdl", "temp"].contains($0.pathExtension.lowercased()) }

                if let finalURL = matched?.first {
                    DispatchQueue.main.async { completion(.success(finalURL)) }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(SimpleError(message: "Không tìm thấy file sau khi tải xong.")))
                    }
                }
            }

            do {
                try process.run()
                onProgress(0.05, "Đang tải video...")
            } catch {
                fileHandle.readabilityHandler = nil
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func parseProgress(_ text: String, onProgress: @escaping (Double, String) -> Void) {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = percentRegex.matches(in: text, range: range).last,
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text),
              let percent = Double(text[swiftRange]) else { return }

        onProgress(min(max(percent / 100.0, 0), 1), "Đang tải video... \(Int(percent))%")
    }
}
