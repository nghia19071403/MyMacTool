import Foundation

/// Tải video Douyin qua DouyinSaver API (không cần yt-dlp).
/// Flow: parse link → lấy aweme_id → download video trực tiếp.
final class DouyinSaverAPI {

    static let shared = DouyinSaverAPI()
    private init() {}

    private let baseURL = "https://api.douyinsaver.com"

    private let douyinPattern = try! NSRegularExpression(
        pattern: #"https?://(?:www\.|v\.)?(?:douyin|iesdouyin)\.com"#,
        options: .caseInsensitive
    )

    func isDouyinURL(_ urlString: String) -> Bool {
        let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        return douyinPattern.firstMatch(in: urlString, range: range) != nil
    }

    func download(
        urlString: String,
        outputDir: URL,
        onProgress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        onProgress(0.05, "Đang phân tích link Douyin...")

        guard let parseURL = URL(string: "\(baseURL)/api/parse") else {
            completion(.failure(SimpleError(message: "Lỗi URL API.")))
            return
        }

        var request = URLRequest(url: parseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://douyinsaver.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let body = ["url": urlString]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let parseTask = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "Lỗi kết nối: \(error.localizedDescription)"))) }
                return
            }

            guard let data, let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "Không nhận được phản hồi từ server."))) }
                return
            }

            guard httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    completion(.failure(SimpleError(
                        message: httpResponse.statusCode == 429
                            ? "Bạn tải quá nhanh, vui lòng đợi vài giây rồi thử lại."
                            : "Lỗi API (code \(httpResponse.statusCode)). Link có thể không hợp lệ."
                    )))
                }
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let awemeId = json["aweme_id"] as? String, !awemeId.isEmpty else {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "Không thể phân tích video từ link này."))) }
                return
            }

            DispatchQueue.main.async { onProgress(0.20, "Đang tải video Douyin...") }

            self.downloadVideoFile(awemeId: awemeId, outputDir: outputDir, onProgress: onProgress, completion: completion)
        }

        parseTask.resume()
    }

    // MARK: - Download File

    private func downloadVideoFile(
        awemeId: String,
        outputDir: URL,
        onProgress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let downloadURLString = "\(baseURL)/api/download/video/\(awemeId)"
        guard let downloadURL = URL(string: downloadURLString) else {
            DispatchQueue.main.async { completion(.failure(SimpleError(message: "Lỗi tạo URL tải video."))) }
            return
        }

        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.setValue("https://douyinsaver.com", forHTTPHeaderField: "Referer")
        downloadRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let fileID = String(UUID().uuidString.prefix(8))
        let destinationURL = outputDir.appendingPathComponent("\(fileID).mp4")

        let downloadTask = URLSession.shared.downloadTask(with: downloadRequest) { tempURL, _, dlError in
            if let dlError {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "Lỗi tải video: \(dlError.localizedDescription)"))) }
                return
            }

            guard let tempURL else {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "Không nhận được file video."))) }
                return
            }

            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                DispatchQueue.main.async {
                    onProgress(1.0, "Tải video thành công!")
                    completion(.success(destinationURL))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "Lỗi lưu file: \(error.localizedDescription)"))) }
            }
        }

        // Theo dõi tiến độ
        let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            let appProgress = 0.20 + progress.fractionCompleted * 0.75
            DispatchQueue.main.async {
                onProgress(min(appProgress, 0.95), "Đang tải video... \(Int(progress.fractionCompleted * 100))%")
            }
        }
        objc_setAssociatedObject(downloadTask, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        downloadTask.resume()
    }
}
