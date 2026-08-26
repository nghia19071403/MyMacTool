# Changelog - MyMacTool

## Phiên bản hiện tại

### 1. Fix lỗi faster-whisper không cài được (PEP 668)

**Vấn đề:** Python Homebrew (PEP 668) chặn `pip install` trực tiếp → app không thể cài faster-whisper.

**Giải pháp:**
- Tạo virtual environment `~/whisper-env` chứa tất cả package Python
- `SystemEnvironment.swift`: Ưu tiên tìm Python từ `~/whisper-env` trước
- Hàm `installFasterWhisper` tự tạo venv nếu pip bị chặn

**File thay đổi:**
- `Services/SystemEnvironment.swift`

---

### 2. Thêm tính năng Lồng tiếng (Dubbing)

**Mô tả:** Chuyển file SRT thành giọng đọc → ghép vào video gốc.

**Quy trình:**
1. User chọn file SRT + video gốc
2. Chọn giọng đọc, tốc độ, giữ audio gốc hay không
3. App dùng `edge-tts` (Python) tạo audio từng câu theo timestamp
4. FFmpeg ghép audio vào video → xuất `_dubbed.mp4`

**File mới:**
- `Models/DubbingTask.swift` — Model task lồng tiếng + enum DubbingVoice
- `Services/DubbingService.swift` — Service chính xử lý lồng tiếng
- `Views/DubbingView.swift` — UI tab lồng tiếng

**File thay đổi:**
- `Models/Enums.swift` — Thêm `SidebarItem.dubbing`
- `Views/ContentView.swift` — Route sang DubbingView
- `ViewModels/AppViewModel.swift` — State + methods cho dubbing
- `Services/SystemEnvironment.swift` — Thêm `verifyEdgeTTS()`, `checkEdgeTTSInstalled()`

---

### 3. Giọng đọc (DubbingVoice)

**25 giọng đọc từ Microsoft Edge TTS:**

| Ngôn ngữ | Giọng |
|-----------|-------|
| 🇻🇳 Việt (6) | Hoài My (chuẩn/cao/trầm), Nam Minh (chuẩn/trầm/cao) |
| 🇺🇸 Anh (8) | Ava, Emma, Aria, Ana, Andrew, Brian, Jenny, Guy |
| 🇨🇳 Trung (5) | Xiaoxiao, Xiaoyi, Yunxi, Yunjian, Yunyang |
| 🇯🇵 Nhật (2) | Nanami, Keita |
| 🇰🇷 Hàn (2) | Sun-Hi, Hyunsu |

**Biến thể giọng Việt** dùng pitch offset:
- `+30Hz` → giọng cao, trẻ
- `-20Hz` / `-30Hz` → giọng trầm, sâu

**Giọng nữ hoạt ngôn:**
- 🇺🇸 Emma — vui vẻ, hoạt ngôn
- 🇺🇸 Aria — tự tin, năng động
- 🇨🇳 Xiaoyi — sống động, hoạt hình

---

### 4. Nghe thử giọng đọc (Preview Voice)

**Mô tả:** Bấm nút ▶️ cạnh dropdown giọng → nghe thử trực tiếp trong app (dùng `NSSound`), không mở Music.

**File thay đổi:**
- `ViewModels/AppViewModel.swift` — `previewVoice()`, `stopPreview()`, `previewPlayer`
- `Views/DubbingView.swift` — Nút play cạnh Picker giọng

---

### 5. Fix dịch SRT bị rate-limit (HTTP 429)

**Vấn đề:** Google Translate API miễn phí chặn IP sau vài request → file `_vi.srt` vẫn chứa tiếng Trung.

**Giải pháp:** Viết lại `SRTTranslator` hoàn toàn — chuyển sang Python script với cascade fallback:

```
1. 🟢 DeepL Free      (tốt nhất, cần API key, 500K ký tự/tháng)
2. 🔵 Google Translate (rất tốt, nếu IP không bị chặn)
3. 🟡 MyMemory        (miễn phí, language code: vi-VN)
4. ⚫ Argos Translate  (offline, zh→en→vi, luôn hoạt động)
```

**Khi engine hiện tại fail → tự chuyển sang engine tiếp theo.**
**Log engine đang dùng hiện trên UI.**

**File thay đổi:**
- `Services/SRTTranslator.swift` — Viết lại hoàn toàn

---

### 6. Fix lồng tiếng crash khi giọng không khớp ngôn ngữ

**Vấn đề:** Dùng giọng Việt đọc text tiếng Trung → edge-tts trả `NoAudioReceived`.

**Giải pháp:**
- Script TTS try/catch từng câu — nếu 1 câu lỗi → tạo silence thay thế, không crash cả quá trình
- Log chi tiết lỗi lên UI (hiện số câu lỗi)
- Capture toàn bộ output khi script fail → hiện 3 dòng cuối cho user debug

**Lưu ý:** Giọng Việt chỉ đọc được text tiếng Việt. Nếu SRT tiếng Trung → dùng giọng Trung hoặc dịch SRT sang Việt trước.

**File thay đổi:**
- `Services/DubbingService.swift`

---

## Dependencies đã cài (~/whisper-env)

```bash
# Tạo bằng:
python3 -m venv ~/whisper-env

# Packages:
~/whisper-env/bin/pip install faster-whisper edge-tts deep-translator argostranslate
```

| Package | Mục đích |
|---------|----------|
| `faster-whisper` | Nhận dạng giọng nói → SRT |
| `edge-tts` | Text-to-speech (Microsoft Neural Voices) |
| `deep-translator` | Dịch (Google, MyMemory fallback) |
| `argostranslate` | Dịch offline (zh→en→vi, luôn hoạt động) |

---

## Argos Translate Models đã cài

```bash
~/whisper-env/bin/python3 -c "
import argostranslate.package
argostranslate.package.update_package_index()
pkgs = argostranslate.package.get_available_packages()
# zh→en
pkg = next(p for p in pkgs if p.from_code == 'zh' and p.to_code == 'en')
argostranslate.package.install_from_path(pkg.download())
# en→vi
pkg = next(p for p in pkgs if p.from_code == 'en' and p.to_code == 'vi')
argostranslate.package.install_from_path(pkg.download())
"
```

---

## Cấu hình DeepL (tùy chọn)

Nếu muốn dùng DeepL (chất lượng dịch tốt nhất):
1. Đăng ký miễn phí tại: https://www.deepl.com/pro#developer
2. Set key trong code:
```swift
SRTTranslator.shared.deeplAPIKey = "your-free-key"
```

---

## Tổng hợp file thay đổi

| File | Loại | Mô tả |
|------|------|-------|
| `Models/DubbingTask.swift` | **MỚI** | Model + DubbingVoice enum (25 giọng) |
| `Services/DubbingService.swift` | **MỚI** | Service lồng tiếng (edge-tts + FFmpeg) |
| `Views/DubbingView.swift` | **MỚI** | UI tab lồng tiếng |
| `Models/Enums.swift` | SỬA | Thêm `SidebarItem.dubbing` |
| `Views/ContentView.swift` | SỬA | Route `.dubbing` → DubbingView |
| `ViewModels/AppViewModel.swift` | SỬA | State + methods dubbing, preview voice |
| `Services/SystemEnvironment.swift` | SỬA | Ưu tiên venv, thêm verifyEdgeTTS |
| `Services/SRTTranslator.swift` | SỬA | Cascade fallback dịch (4 engine) |
