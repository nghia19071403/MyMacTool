# MyMacTool — Project Overview

## Tổng quan

App macOS native viết bằng **SwiftUI** (MVVM pattern). Chức năng chính:
1. **Tải video** từ Bilibili / Douyin (dùng yt-dlp, DouyinSaverAPI)
2. **Nhận dạng giọng nói** → tạo file SRT (dùng faster-whisper)
3. **Dịch phụ đề** tiếng Trung → tiếng Việt (cascade: DeepL → Google → MyMemory → Argos offline)
4. **Lồng tiếng** — chuyển SRT thành giọng đọc, ghép vào video (dùng edge-tts + FFmpeg)

---

## Tech Stack

| Thành phần | Công nghệ |
|-----------|-----------|
| UI | SwiftUI, NavigationSplitView |
| Architecture | MVVM (`@MainActor AppViewModel`) |
| TTS | edge-tts (Python, Microsoft Neural Voices) |
| STT | faster-whisper (Python) |
| Dịch | deep-translator, argostranslate (Python) |
| Tải video | yt-dlp (binary/module), DouyinSaverAPI |
| Audio/Video | FFmpeg (CLI) |
| Python env | `~/whisper-env` (venv, tất cả package cài ở đây) |
| Target | macOS 13+, Apple Silicon |

---

## Cấu trúc thư mục

```
MyMacTool/
├── MyMacToolApp.swift          — Entry point (@main)
├── Models/
│   ├── Enums.swift             — TaskStatus, SRTOutputOption, LinkPlatform, SidebarItem, WhisperModel, DubbingVoice
│   ├── VideoTask.swift         — Model video task (Whisper STT)
│   ├── DownloadTask.swift      — Model download task (Bilibili/Douyin)
│   └── DubbingTask.swift       — Model lồng tiếng task
├── ViewModels/
│   └── AppViewModel.swift      — ViewModel chính, chứa toàn bộ state + logic
├── Views/
│   ├── ContentView.swift       — Layout chính (NavigationSplitView)
│   ├── SidebarView.swift       — Sidebar 4 tab
│   ├── LinkInputView.swift     — UI dán link tải video
│   ├── DropVideoView.swift     — UI kéo-thả file video
│   ├── DubbingView.swift       — UI lồng tiếng
│   ├── TabBarView.swift        — Tab bar video tasks
│   ├── TabChipView.swift       — Chip UI cho tab
│   ├── TaskDetailView.swift    — Chi tiết video task
│   └── DownloadTaskRow.swift   — Row UI download task
└── Services/
    ├── SystemEnvironment.swift — Dò Python, FFmpeg, yt-dlp, edge-tts, faster-whisper
    ├── TranscriptionService.swift — Queue engine chạy Whisper (song song, giới hạn concurrent)
    ├── SRTTranslator.swift     — Dịch SRT (Python, cascade 4 engine)
    ├── DubbingService.swift    — Lồng tiếng (Python edge-tts + FFmpeg)
    ├── LinkDownloader.swift    — Tải video bằng yt-dlp
    └── DouyinSaverAPI.swift    — Tải video Douyin qua API
```

---

## Luồng hoạt động

### Tab Bilibili / Douyin
```
User dán link → yt-dlp/DouyinAPI tải video → auto chuyển sang Whisper → tạo SRT → dịch (nếu bật)
```

### Tab Kéo file
```
User kéo/chọn video → TranscriptionService queue → faster-whisper tạo SRT → SRTTranslator dịch
```

### Tab Lồng tiếng
```
User chọn SRT + video → DubbingService:
  1. Parse SRT (Python)
  2. edge-tts tạo audio từng câu
  3. FFmpeg ghép audio theo timestamp
  4. FFmpeg merge với video → output _dubbed.mp4
```

---

## Các service chính

### SystemEnvironment (singleton)
- Dò tìm + cache đường dẫn: Python, FFmpeg, yt-dlp, faster-whisper, edge-tts
- Ưu tiên `~/whisper-env/bin/python3` (venv chứa tất cả package)
- Tự tạo venv + cài package nếu pip bị chặn (PEP 668)

### TranscriptionService
- Queue engine: giới hạn N video chạy Whisper đồng thời (default 2)
- Mỗi task chạy 1 Process riêng (Python inline script)
- Parse stdout để update progress realtime

### SRTTranslator
- Chạy Python script với cascade fallback:
  1. DeepL Free (cần API key, `SRTTranslator.shared.deeplAPIKey`)
  2. Google Translate (deep-translator)
  3. MyMemory (language code `zh-CN` → `vi-VN`)
  4. Argos Translate (offline, chain zh→en→vi)
- Tự fallback khi engine bị rate-limit/lỗi
- Log engine đang dùng lên UI

### DubbingService
- Edge-tts: 25 voices (Việt/Anh/Trung/Nhật/Hàn), hỗ trợ pitch offset tạo biến thể giọng
- Try/catch từng câu TTS (lỗi 1 câu → silence, không crash)
- FFmpeg adelay + amix ghép audio đúng timestamp
- Option giữ audio gốc (mix volume) hoặc thay hoàn toàn

---

## Dependencies (~/whisper-env)

```bash
python3 -m venv ~/whisper-env
~/whisper-env/bin/pip install faster-whisper edge-tts deep-translator argostranslate
```

Argos models: `zh→en`, `en→vi` (cài 1 lần, chạy offline)

---

## Lưu ý quan trọng

- **Python path**: App ưu tiên `~/whisper-env/bin/python3`. Homebrew Python bị PEP 668 chặn pip.
- **FFmpeg**: Cần cài qua `brew install ffmpeg`
- **edge-tts**: Cần internet (gọi Microsoft server). Giọng Việt chỉ đọc text Việt, giọng Trung chỉ đọc text Trung.
- **Dịch**: Google hay bị 429 → app tự fallback. Argos offline luôn hoạt động.
- **Xcode**: Project dùng auto file discovery (PBXSourcesBuildPhase rỗng) → thêm file mới vào folder là Xcode tự nhận.
- **DeepL key**: Optional, set `SRTTranslator.shared.deeplAPIKey = "..."` để dùng engine tốt nhất.
