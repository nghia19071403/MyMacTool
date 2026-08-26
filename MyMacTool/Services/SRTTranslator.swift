import Foundation

/// Dịch file SRT tiếng Trung → tiếng Việt qua Google Translate (miễn phí).
final class SRTTranslator {

    static let shared = SRTTranslator()
    private init() {}

    // MARK: - Public API

    func translate(
        srtURL: URL,
        onProgress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Đọc file
            guard let content = try? String(contentsOf: srtURL, encoding: .utf8) else {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "Không đọc được file SRT."))) }
                return
            }

            // 2. Parse
            let blocks = self.parseSRT(content)
            guard !blocks.isEmpty else {
                DispatchQueue.main.async { completion(.failure(SimpleError(message: "File SRT rỗng hoặc không hợp lệ."))) }
                return
            }

            DispatchQueue.main.async { onProgress(0.05, "Đang dịch phụ đề sang tiếng Việt...") }

            // 3. Dịch theo batch (20 dòng/batch để tránh text quá dài bị lỗi)
            let batchSize = 20
            let textLines = blocks.map { $0.text }
            let batches = stride(from: 0, to: textLines.count, by: batchSize).map {
                Array(textLines[$0..<min($0 + batchSize, textLines.count)])
            }

            let totalBatches = batches.count
            let group = DispatchGroup()
            var batchResults: [(Int, [String])] = []
            let lock = NSLock()
            var hasError: Error?

            for (index, batch) in batches.enumerated() {
                group.enter()

                self.translateBatch(texts: batch) { result in
                    switch result {
                    case .success(let translated):
                        lock.lock()
                        batchResults.append((index, translated))
                        lock.unlock()

                        let progress = Double(index + 1) / Double(totalBatches)
                        DispatchQueue.main.async {
                            onProgress(0.05 + progress * 0.85, "Đang dịch... \(Int(progress * 100))%")
                        }
                    case .failure(let error):
                        lock.lock()
                        if hasError == nil { hasError = error }
                        lock.unlock()
                    }
                    group.leave()
                }

                // Delay tránh rate-limit
                Thread.sleep(forTimeInterval: 0.5)
            }

            group.wait()

            if let error = hasError {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            // 4. Ghép lại
            batchResults.sort { $0.0 < $1.0 }
            let translatedLines = batchResults.flatMap { $0.1 }

            var outputContent = ""
            for (i, block) in blocks.enumerated() {
                let translated = i < translatedLines.count ? translatedLines[i] : block.text
                outputContent += "\(block.index)\n\(block.timestamp)\n\(translated)\n\n"
            }

            // 5. Ghi file _vi.srt
            let originalName = srtURL.deletingPathExtension().lastPathComponent
            let outputURL = srtURL.deletingLastPathComponent().appendingPathComponent("\(originalName)_vi.srt")

            do {
                try outputContent.write(to: outputURL, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    onProgress(1.0, "Dịch xong!")
                    completion(.success(outputURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(SimpleError(message: "Không ghi được file dịch: \(error.localizedDescription)")))
                }
            }
        }
    }

    // MARK: - SRT Parsing

    private struct SRTBlock {
        let index: String
        let timestamp: String
        let text: String
    }

    private func parseSRT(_ content: String) -> [SRTBlock] {
        var blocks: [SRTBlock] = []
        let rawBlocks = content.components(separatedBy: "\n\n")

        for rawBlock in rawBlocks {
            let lines = rawBlock.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            let index = lines[0].trimmingCharacters(in: .whitespaces)
            let timestamp = lines[1].trimmingCharacters(in: .whitespaces)
            let text = lines[2...].joined(separator: "\n").trimmingCharacters(in: .whitespaces)

            guard timestamp.contains("-->") else { continue }
            blocks.append(SRTBlock(index: index, timestamp: timestamp, text: text))
        }
        return blocks
    }

    // MARK: - Google Translate

    private func translateBatch(texts: [String], completion: @escaping (Result<[String], Error>) -> Void) {
        let separator = "\n"
        let joinedText = texts.joined(separator: separator)

        // Dùng POST request để tránh lỗi URL quá dài (GET bị giới hạn ~2000 ký tự)
        guard let url = URL(string: "https://translate.googleapis.com/translate_a/single") else {
            completion(.failure(SimpleError(message: "Lỗi tạo URL dịch.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        // Encode body parameters (an toàn hơn gửi qua URL)
        let params = "client=gtx&sl=zh-CN&tl=vi&dt=t&q=\(joinedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? joinedText)"
        request.httpBody = params.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(SimpleError(message: "Lỗi Google Translate: \(error.localizedDescription)")))
                return
            }

            guard let data else {
                completion(.failure(SimpleError(message: "Google Translate không trả về data.")))
                return
            }

            // Debug: in ra nếu không parse được
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
                let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? "binary"
                let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("❌ Google Translate parse fail (HTTP \(httpCode)): \(bodyStr)")
                completion(.failure(SimpleError(message: "Google Translate lỗi (HTTP \(httpCode)). Có thể bị rate-limit.")))
                return
            }

            guard let sentences = json.first as? [[Any]] else {
                print("❌ Google Translate: json.first không phải [[Any]], json = \(json)")
                completion(.failure(SimpleError(message: "Kết quả dịch không đúng format.")))
                return
            }

            let translatedText = sentences.compactMap { $0.first as? String }.joined()
            let translatedLines = translatedText.components(separatedBy: separator)

            var result = translatedLines
            while result.count < texts.count {
                result.append(texts[result.count])
            }
            if result.count > texts.count {
                result = Array(result.prefix(texts.count))
            }

            completion(.success(result))
        }.resume()
    }
}
