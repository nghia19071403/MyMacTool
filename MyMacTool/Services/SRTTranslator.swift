import Foundation

/// Dịch file SRT tiếng Trung → tiếng Việt.
/// Cascade fallback theo thứ tự:
///   1. OpenAI GPT (chất lượng cao nhất, cần API key)
///   2. Google Translate (deep-translator, rất tốt)
///   3. MyMemory (miễn phí, language code vi-VN)
///   4. Argos Translate (offline, zh→en→vi, luôn hoạt động)
///
/// Khi engine hiện tại fail/hết quota → tự chuyển sang engine tiếp theo.
final class SRTTranslator {

    static let shared = SRTTranslator()
    private init() {
        // Load API key đã lưu
        openaiAPIKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        openaiModel = UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4o-mini"
    }

    /// OpenAI API Key — set qua UI. Để trống = bỏ qua GPT.
    var openaiAPIKey: String = "" {
        didSet { UserDefaults.standard.set(openaiAPIKey, forKey: "openai_api_key") }
    }

    /// Model OpenAI dùng để dịch
    var openaiModel: String = "gpt-4o-mini" {
        didSet { UserDefaults.standard.set(openaiModel, forKey: "openai_model") }
    }

    // MARK: - Public API

    func translate(
        srtURL: URL,
        onProgress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async { onProgress(0.05, "Đang chuẩn bị dịch...") }

            guard let python = SystemEnvironment.shared.resolvePython() else {
                DispatchQueue.main.async {
                    completion(.failure(SimpleError(message: "Không tìm thấy Python3.")))
                }
                return
            }

            let originalName = srtURL.deletingPathExtension().lastPathComponent
            let outputURL = srtURL.deletingLastPathComponent().appendingPathComponent("\(originalName)_vi.srt")

            // Retry toàn bộ tối đa 3 lần nếu tất cả engine fail (phòng lỗi mạng tạm thời)
            let maxAttempts = 3
            var success = false
            for attempt in 1...maxAttempts {
                if attempt > 1 {
                    DispatchQueue.main.async {
                        onProgress(-1, "Dịch lỗi, đang thử lại (lần \(attempt)/\(maxAttempts))...")
                    }
                    Thread.sleep(forTimeInterval: Double(attempt) * 2.0) // backoff 2s, 4s
                }
                success = self.runTranslateScript(
                    python: python,
                    srtPath: srtURL.path,
                    outputPath: outputURL.path,
                    openaiKey: self.openaiAPIKey,
                    openaiModel: self.openaiModel,
                    onProgress: onProgress
                )
                if success { break }
            }

            DispatchQueue.main.async {
                if success {
                    onProgress(1.0, "Dịch xong!")
                    completion(.success(outputURL))
                } else {
                    completion(.failure(SimpleError(message: "Tất cả engine dịch đều thất bại (đã thử \(maxAttempts) lần).")))
                }
            }
        }
    }

    // MARK: - Python Script

    private func runTranslateScript(
        python: String,
        srtPath: String,
        outputPath: String,
        openaiKey: String,
        openaiModel: String,
        onProgress: @escaping (Double, String) -> Void
    ) -> Bool {
        let script = """
        import sys
        import time
        import json

        SRT_PATH = r\"\"\"\(srtPath)\"\"\"
        OUTPUT_PATH = r\"\"\"\(outputPath)\"\"\"
        OPENAI_KEY = "\(openaiKey)"
        OPENAI_MODEL = "\(openaiModel)"

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
                index = lines[0].strip()
                timestamp = lines[1].strip()
                if '-->' not in timestamp:
                    continue
                text = '\\n'.join(lines[2:]).strip()
                segments.append({'index': index, 'timestamp': timestamp, 'text': text})
            return segments

        # --- Helper: retry 1 câu với exponential backoff ---
        # Trả về (text_dịch, is_fatal). is_fatal=True => lỗi nghiêm trọng (quota/blocked) → fallback engine.
        def translate_one(fn, text, max_retries=3):
            if not text.strip():
                return text, False
            delay = 1.0
            for attempt in range(max_retries):
                try:
                    r = fn(text)
                    if r and r.strip():
                        return r, False
                    # Kết quả rỗng → thử lại
                except Exception as e:
                    err = str(e).lower()
                    # Lỗi nghiêm trọng → không retry, báo fatal để chuyển engine
                    if 'quota' in err or 'blocked' in err or '403' in err:
                        return None, True
                    # Rate-limit / mạng → retry sau delay
                    if attempt < max_retries - 1:
                        time.sleep(delay)
                        delay *= 2  # backoff: 1s, 2s, 4s
                        continue
            return None, False  # hết retry mà vẫn fail (không fatal)

        # --- Engine 1: OpenAI GPT ---
        def translate_openai(texts):
            if not OPENAI_KEY:
                return None
            print(f"[engine] 🟢 Đang dùng: OpenAI {OPENAI_MODEL}", flush=True)
            try:
                import urllib.request
                results = []
                # Dịch theo batch 20 câu để tiết kiệm request
                batch_size = 20
                for start in range(0, len(texts), batch_size):
                    batch = texts[start:start+batch_size]
                    # Đánh số từng câu để GPT giữ đúng thứ tự
                    numbered = "\\n".join(f"{i+1}. {t}" for i, t in enumerate(batch))
                    prompt = (
                        "Dịch các câu phụ đề tiếng Trung sau sang tiếng Việt tự nhiên, "
                        "giữ nguyên số thứ tự, mỗi câu 1 dòng, KHÔNG thêm giải thích. "
                        "Chỉ trả về bản dịch theo định dạng '<số>. <bản dịch>':\\n\\n" + numbered
                    )
                    payload = {
                        "model": OPENAI_MODEL,
                        "messages": [
                            {"role": "system", "content": "Bạn là dịch giả phụ đề chuyên nghiệp Trung-Việt."},
                            {"role": "user", "content": prompt}
                        ],
                        "temperature": 0.3
                    }
                    req = urllib.request.Request(
                        "https://api.openai.com/v1/chat/completions",
                        data=json.dumps(payload).encode('utf-8'),
                        headers={
                            "Content-Type": "application/json",
                            "Authorization": f"Bearer {OPENAI_KEY}"
                        },
                        method="POST"
                    )
                    try:
                        with urllib.request.urlopen(req, timeout=60) as resp:
                            data = json.loads(resp.read().decode('utf-8'))
                        content = data['choices'][0]['message']['content'].strip()
                    except Exception as e:
                        err = str(e)
                        if '401' in err:
                            print("[warn] OpenAI API key không hợp lệ!", flush=True)
                        elif '429' in err:
                            print("[warn] OpenAI hết quota/rate-limit!", flush=True)
                        else:
                            print(f"[warn] OpenAI lỗi: {err[:80]}", flush=True)
                        return None

                    # Parse kết quả có đánh số
                    lines = [l.strip() for l in content.split('\\n') if l.strip()]
                    batch_results = []
                    for line in lines:
                        # Bỏ số thứ tự đầu dòng "1. "
                        if '. ' in line[:5]:
                            line = line.split('. ', 1)[1]
                        batch_results.append(line)
                    # Đảm bảo đủ số câu
                    while len(batch_results) < len(batch):
                        batch_results.append(batch[len(batch_results)])
                    results.extend(batch_results[:len(batch)])

                    progress = int((start + batch_size) / len(texts) * 80)
                    print(f"[progress] {min(progress, 80)}%", flush=True)
                    time.sleep(0.3)
                return results
            except Exception as e:
                print(f"[warn] OpenAI exception: {str(e)[:80]}", flush=True)
                return None

        # --- Engine: Google Translate ---
        def translate_google(texts):
            print("[engine] 🔵 Đang dùng: Google Translate", flush=True)
            try:
                from deep_translator import GoogleTranslator
                translator = GoogleTranslator(source='zh-CN', target='vi')

                # Kiểm tra nhanh 1 câu: nếu Google không dịch được (đang hỏng) → bỏ ngay
                probe_ok = False
                for t in texts:
                    if not t.strip():
                        continue
                    try:
                        r = translator.translate(t)
                        if r and r.strip() and r.strip() != t.strip():
                            probe_ok = True
                        break
                    except Exception as e:
                        print(f"[warn] Google probe lỗi: {str(e)[:80]}", flush=True)
                        break
                if not probe_ok:
                    print("[warn] Google không khả dụng, chuyển engine", flush=True)
                    return None

                results = []
                fail_count = 0
                for i, text in enumerate(texts):
                    translated, fatal = translate_one(translator.translate, text)
                    if fatal:
                        print(f"[warn] Google lỗi nghiêm trọng tại câu {i+1}, chuyển engine", flush=True)
                        return None
                    if translated and translated.strip():
                        results.append(translated)
                    else:
                        results.append(text)
                        fail_count += 1
                    # Nếu quá nhiều câu fail (kể cả sau retry) → engine hỏng, fallback
                    if fail_count > max(3, len(texts) // 4):
                        print(f"[warn] Google fail {fail_count} câu, chuyển engine", flush=True)
                        return None
                    if (i + 1) % 5 == 0:
                        progress = int((i + 1) / len(texts) * 80)
                        print(f"[progress] {min(progress, 80)}%", flush=True)
                    time.sleep(0.5)
                return results
            except Exception as e:
                print(f"[warn] Google exception: {str(e)[:80]}", flush=True)
                return None

        # --- Engine 2: MyMemory ---
        def translate_mymemory(texts):
            print("[engine] 🟡 Đang dùng: MyMemory Translate", flush=True)
            try:
                from deep_translator import MyMemoryTranslator
                translator = MyMemoryTranslator(source='zh-CN', target='vi-VN')
                results = []
                fail_count = 0
                for i, text in enumerate(texts):
                    translated, fatal = translate_one(translator.translate, text)
                    if fatal:
                        print(f"[warn] MyMemory hết quota tại câu {i+1}, chuyển engine", flush=True)
                        return None
                    if translated and translated.strip():
                        results.append(translated)
                    else:
                        results.append(text)
                        fail_count += 1
                    if fail_count > max(3, len(texts) // 4):
                        print(f"[warn] MyMemory fail {fail_count} câu, chuyển engine", flush=True)
                        return None
                    if (i + 1) % 5 == 0:
                        progress = int((i + 1) / len(texts) * 80)
                        print(f"[progress] {min(progress, 80)}%", flush=True)
                    time.sleep(1.0)
                return results
            except Exception as e:
                print(f"[warn] MyMemory exception: {str(e)[:80]}", flush=True)
                return None

        # --- Engine 3: Argos Translate (OFFLINE) ---
        def translate_argos(texts):
            print("[engine] ⚫ Đang dùng: Argos Translate (offline, zh→en→vi)", flush=True)
            try:
                import argostranslate.translate
                results = []
                for i, text in enumerate(texts):
                    try:
                        en_text = argostranslate.translate.translate(text, 'zh', 'en')
                        vi_text = argostranslate.translate.translate(en_text, 'en', 'vi')
                        results.append(vi_text if vi_text else text)
                    except Exception:
                        results.append(text)
                    if (i + 1) % 5 == 0:
                        progress = int((i + 1) / len(texts) * 80)
                        print(f"[progress] {min(progress, 80)}%", flush=True)
                return results
            except Exception as e:
                print(f"[error] Argos exception: {str(e)[:80]}", flush=True)
                return None

        # --- Main: Cascade ---
        def main():
            print("[progress] 5%", flush=True)
            print("[info] Đang đọc file SRT...", flush=True)

            segments = parse_srt(SRT_PATH)
            if not segments:
                print("[error] File SRT rỗng!", flush=True)
                sys.exit(1)

            print(f"[info] Tìm thấy {len(segments)} câu cần dịch", flush=True)
            print("[progress] 10%", flush=True)

            texts = [seg['text'] for seg in segments]

            engines = [
                ("OpenAI GPT", translate_openai),
                ("MyMemory", translate_mymemory),
                ("Google", translate_google),
                ("Argos (offline)", translate_argos),
            ]

            translated = None
            used_engine = None
            for name, fn in engines:
                result = fn(texts)
                if result is not None and len(result) == len(texts):
                    translated = result
                    used_engine = name
                    break
                else:
                    print(f"[fallback] {name} thất bại, thử engine tiếp theo...", flush=True)

            if translated is None:
                print("[error] Tất cả engine đều thất bại!", flush=True)
                sys.exit(1)

            print(f"[info] Dịch xong bằng {used_engine}!", flush=True)
            print("[progress] 90%", flush=True)

            with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
                for i, seg in enumerate(segments):
                    trans = translated[i] if i < len(translated) else seg['text']
                    f.write(f"{seg['index']}\\n{seg['timestamp']}\\n{trans}\\n\\n")

            print("[progress] 100%", flush=True)
            print(f"[done] Hoàn tất! Engine: {used_engine}", flush=True)

        main()
        """

        let scriptFile = FileManager.default.temporaryDirectory.appendingPathComponent("translate_srt.py")
        try? script.write(to: scriptFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptFile.path]

        process.environment = SystemEnvironment.pythonEnvironment(for: python)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let fileHandle = pipe.fileHandleForReading

        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if trimmed.contains("[progress]"),
                   let match = trimmed.range(of: #"\d+"#, options: .regularExpression) {
                    let percent = Double(trimmed[match]) ?? 0
                    DispatchQueue.main.async { onProgress(percent / 100.0, "") }
                } else if trimmed.contains("[engine]") {
                    let msg = trimmed.replacingOccurrences(of: "[engine] ", with: "")
                    DispatchQueue.main.async { onProgress(-1, msg) }
                } else if trimmed.contains("[info]") {
                    let msg = trimmed.replacingOccurrences(of: "[info] ", with: "")
                    DispatchQueue.main.async { onProgress(-1, msg) }
                } else if trimmed.contains("[fallback]") {
                    let msg = trimmed.replacingOccurrences(of: "[fallback] ", with: "")
                    DispatchQueue.main.async { onProgress(-1, "⚠️ \(msg)") }
                } else if trimmed.contains("[done]") {
                    let msg = trimmed.replacingOccurrences(of: "[done] ", with: "")
                    DispatchQueue.main.async { onProgress(1.0, "✅ \(msg)") }
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            fileHandle.readabilityHandler = nil
            try? FileManager.default.removeItem(at: scriptFile)
            return process.terminationStatus == 0
        } catch {
            fileHandle.readabilityHandler = nil
            print("❌ Translate script error:", error)
            return false
        }
    }
}
