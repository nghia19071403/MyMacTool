import Foundation

/// Dịch vụ thống kê xu hướng:
/// - Bilibili: lấy video hot (popular API) → GPT gom chủ đề + dịch tiêu đề.
/// - Douyin: lấy từ khóa hot (hot-search billboard) → GPT dịch + gom chủ đề.
final class TrendingService {

    static let shared = TrendingService()
    private init() {}

    /// API key OpenAI (đồng bộ từ AppViewModel/SRTTranslator).
    var openaiAPIKey: String = ""
    var openaiModel: String = "gpt-4o"

    // MARK: - Public API

    /// Lấy + phân tích xu hướng Bilibili.
    /// - pages: số trang popular (mỗi trang ~20 video).
    func fetchBilibiliTrending(
        pages: Int = 3,
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Result<TrendingResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async { onProgress("Đang lấy video hot từ Bilibili...") }

            // 1. Lấy danh sách video hot
            var videos: [TrendingVideo] = []
            for page in 1...max(1, pages) {
                switch self.fetchPopularPage(page: page) {
                case .success(let items):
                    videos.append(contentsOf: items)
                case .failure(let err):
                    // Nếu trang đầu lỗi → dừng, báo lỗi. Trang sau lỗi → dùng cái đã có.
                    if page == 1 {
                        DispatchQueue.main.async { completion(.failure(err)) }
                        return
                    }
                }
                DispatchQueue.main.async { onProgress("Đã lấy \(videos.count) video hot...") }
            }

            guard !videos.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(SimpleError(message: "Không lấy được video hot nào từ Bilibili.")))
                }
                return
            }

            // 2. Phân tích bằng GPT (nếu có key). Không có key → chỉ trả video thô.
            guard !self.openaiAPIKey.isEmpty else {
                let result = TrendingResult(videos: videos, topics: [], generatedAt: Date())
                DispatchQueue.main.async {
                    onProgress("Xong (chưa phân tích — cần OpenAI key để gom chủ đề)")
                    completion(.success(result))
                }
                return
            }

            DispatchQueue.main.async { onProgress("Đang phân tích chủ đề bằng GPT...") }

            self.analyzeWithGPT(videos: videos) { analyzed, topics in
                let result = TrendingResult(videos: analyzed, topics: topics, generatedAt: Date())
                DispatchQueue.main.async {
                    onProgress("Hoàn tất!")
                    completion(.success(result))
                }
            }
        }
    }

    /// Lấy + phân tích xu hướng Douyin (từ khóa hot).
    func fetchDouyinTrending(
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Result<TrendingResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async { onProgress("Đang lấy từ khóa hot từ Douyin...") }

            switch self.fetchDouyinHotWords() {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let keywords):
                guard !keywords.isEmpty else {
                    DispatchQueue.main.async {
                        completion(.failure(SimpleError(message: "Không lấy được từ khóa hot nào từ Douyin.")))
                    }
                    return
                }

                // Không có key → trả từ khóa thô
                guard !self.openaiAPIKey.isEmpty else {
                    let result = TrendingResult(keywords: keywords, generatedAt: Date())
                    DispatchQueue.main.async {
                        onProgress("Xong (chưa dịch — cần OpenAI key)")
                        completion(.success(result))
                    }
                    return
                }

                DispatchQueue.main.async { onProgress("Đang dịch & phân tích bằng GPT...") }

                self.analyzeKeywordsWithGPT(keywords: keywords) { translated, topics in
                    let result = TrendingResult(keywords: translated, topics: topics, generatedAt: Date())
                    DispatchQueue.main.async {
                        onProgress("Hoàn tất!")
                        completion(.success(result))
                    }
                }
            }
        }
    }

    // MARK: - Douyin Hot Words API

    private func fetchDouyinHotWords() -> Result<[TrendingKeyword], Error> {
        let urlStr = "https://www.iesdouyin.com/web/api/v2/hotsearch/billboard/word/"
        guard let url = URL(string: urlStr) else {
            return .failure(SimpleError(message: "URL không hợp lệ"))
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[TrendingKeyword], Error> = .failure(SimpleError(message: "Không có phản hồi"))

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error = error { result = .failure(error); return }
            guard let data = data else {
                result = .failure(SimpleError(message: "Dữ liệu rỗng")); return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let wordList = json["word_list"] as? [[String: Any]] else {
                    result = .failure(SimpleError(message: "Định dạng phản hồi Douyin không hợp lệ"))
                    return
                }
                let keywords: [TrendingKeyword] = wordList.compactMap { item in
                    guard let word = item["word"] as? String else { return nil }
                    return TrendingKeyword(
                        word: word,
                        wordVi: nil,
                        hotValue: (item["hot_value"] as? Int) ?? 0
                    )
                }
                result = .success(keywords)
            } catch {
                result = .failure(error)
            }
        }.resume()

        semaphore.wait()
        return result
    }

    // MARK: - GPT Analysis (Douyin keywords)

    private func analyzeKeywordsWithGPT(
        keywords: [TrendingKeyword],
        completion: @escaping ([TrendingKeyword], [TrendingTopic]) -> Void
    ) {
        let listText = keywords.enumerated().map { i, k in
            "\(i). \(k.word) (hot: \(k.hotValue))"
        }.joined(separator: "\n")

        let prompt = """
        Dưới đây là danh sách từ khóa đang thịnh hành trên Douyin (TikTok Trung Quốc), \
        định dạng "<số>. <từ khóa tiếng Trung> (hot: <điểm nóng>)":

        \(listText)

        Hãy trả về JSON THUẦN (không markdown) với cấu trúc:
        {
          "translations": { "<số>": "<từ khóa dịch tiếng Việt>", ... },
          "topics": [
            {
              "name": "<tên chủ đề tiếng Việt>",
              "keywords": ["<từ khóa liên quan>", ...],
              "videoCount": <số từ khóa thuộc chủ đề>,
              "summary": "<1 câu vì sao chủ đề này đang hot>"
            }
          ]
        }
        Gom các từ khóa thành 5-8 chủ đề nổi bật, sắp theo mức độ quan tâm (tổng điểm hot).
        """

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(keywords, []); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openaiAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let payload: [String: Any] = [
            "model": openaiModel,
            "messages": [
                ["role": "system", "content": "Bạn là chuyên gia phân tích xu hướng nội dung mạng xã hội. Luôn trả về JSON hợp lệ."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let semaphore = DispatchSemaphore(value: 0)
        var outKeywords = keywords
        var outTopics: [TrendingTopic] = []

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  var content = message["content"] as? String else {
                return
            }
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.hasPrefix("```") {
                content = content.replacingOccurrences(of: "```json", with: "")
                content = content.replacingOccurrences(of: "```", with: "")
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let cdata = content.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: cdata) as? [String: Any] else {
                return
            }
            if let translations = parsed["translations"] as? [String: String] {
                outKeywords = keywords.enumerated().map { i, k in
                    if let vi = translations["\(i)"] {
                        return TrendingKeyword(word: k.word, wordVi: vi, hotValue: k.hotValue)
                    }
                    return k
                }
            }
            if let topics = parsed["topics"] as? [[String: Any]] {
                outTopics = topics.compactMap { t in
                    guard let name = t["name"] as? String else { return nil }
                    return TrendingTopic(
                        name: name,
                        keywords: (t["keywords"] as? [String]) ?? [],
                        videoCount: (t["videoCount"] as? Int) ?? 0,
                        summary: (t["summary"] as? String) ?? ""
                    )
                }
            }
        }.resume()

        semaphore.wait()
        completion(outKeywords, outTopics)
    }

    // MARK: - Bilibili Popular API

    private func fetchPopularPage(page: Int) -> Result<[TrendingVideo], Error> {
        let urlStr = "https://api.bilibili.com/x/web-interface/popular?ps=20&pn=\(page)"
        guard let url = URL(string: urlStr) else {
            return .failure(SimpleError(message: "URL không hợp lệ"))
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[TrendingVideo], Error> = .failure(SimpleError(message: "Không có phản hồi"))

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error = error {
                result = .failure(error); return
            }
            guard let data = data else {
                result = .failure(SimpleError(message: "Dữ liệu rỗng")); return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let code = json["code"] as? Int, code == 0,
                      let dataObj = json["data"] as? [String: Any],
                      let list = dataObj["list"] as? [[String: Any]] else {
                    result = .failure(SimpleError(message: "Định dạng phản hồi Bilibili không hợp lệ"))
                    return
                }
                let videos: [TrendingVideo] = list.compactMap { item in
                    guard let bvid = item["bvid"] as? String,
                          let title = item["title"] as? String else { return nil }
                    let owner = item["owner"] as? [String: Any]
                    let stat = item["stat"] as? [String: Any]
                    return TrendingVideo(
                        id: bvid,
                        title: title,
                        titleVi: nil,
                        author: (owner?["name"] as? String) ?? "",
                        view: (stat?["view"] as? Int) ?? 0,
                        tname: (item["tname"] as? String) ?? "",
                        url: "https://www.bilibili.com/video/\(bvid)"
                    )
                }
                result = .success(videos)
            } catch {
                result = .failure(error)
            }
        }.resume()

        semaphore.wait()
        return result
    }

    // MARK: - GPT Analysis

    /// Gửi danh sách video cho GPT, nhận về: tiêu đề dịch + danh sách chủ đề.
    private func analyzeWithGPT(
        videos: [TrendingVideo],
        completion: @escaping ([TrendingVideo], [TrendingTopic]) -> Void
    ) {
        // Chuẩn bị danh sách rút gọn cho prompt (index + tiêu đề + view + phân loại)
        let listText = videos.enumerated().map { i, v in
            "\(i). [\(v.tname)] \(v.title) (view: \(v.view))"
        }.joined(separator: "\n")

        let prompt = """
        Dưới đây là danh sách video đang thịnh hành trên Bilibili (Trung Quốc), \
        định dạng "<số>. [phân loại] <tiêu đề tiếng Trung> (view: <lượt xem>)":

        \(listText)

        Hãy trả về JSON THUẦN (không markdown, không giải thích) với cấu trúc:
        {
          "translations": { "<số>": "<tiêu đề dịch sang tiếng Việt>", ... },
          "topics": [
            {
              "name": "<tên chủ đề tiếng Việt>",
              "keywords": ["<từ khóa>", ...],
              "videoCount": <số video thuộc chủ đề>,
              "summary": "<1 câu vì sao chủ đề này đang hot>"
            }
          ]
        }
        Gom các video thành 5-8 chủ đề nổi bật nhất, sắp theo mức độ được quan tâm (tổng view + số video).
        """

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(videos, []); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openaiAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let payload: [String: Any] = [
            "model": openaiModel,
            "messages": [
                ["role": "system", "content": "Bạn là chuyên gia phân tích xu hướng nội dung mạng xã hội. Luôn trả về JSON hợp lệ."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let semaphore = DispatchSemaphore(value: 0)
        var outVideos = videos
        var outTopics: [TrendingTopic] = []

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  var content = message["content"] as? String else {
                return
            }

            // Bỏ rào markdown nếu GPT lỡ bọc ```json ... ```
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.hasPrefix("```") {
                content = content.replacingOccurrences(of: "```json", with: "")
                content = content.replacingOccurrences(of: "```", with: "")
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let cdata = content.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: cdata) as? [String: Any] else {
                return
            }

            // Áp bản dịch tiêu đề
            if let translations = parsed["translations"] as? [String: String] {
                outVideos = videos.enumerated().map { i, v in
                    var copy = v
                    if let vi = translations["\(i)"] {
                        copy = TrendingVideo(id: v.id, title: v.title, titleVi: vi,
                                             author: v.author, view: v.view, tname: v.tname, url: v.url)
                    }
                    return copy
                }
            }

            // Parse topics
            if let topics = parsed["topics"] as? [[String: Any]] {
                outTopics = topics.compactMap { t in
                    guard let name = t["name"] as? String else { return nil }
                    return TrendingTopic(
                        name: name,
                        keywords: (t["keywords"] as? [String]) ?? [],
                        videoCount: (t["videoCount"] as? Int) ?? 0,
                        summary: (t["summary"] as? String) ?? ""
                    )
                }
            }
        }.resume()

        semaphore.wait()
        completion(outVideos, outTopics)
    }
}
