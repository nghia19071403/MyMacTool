import SwiftUI
import UniformTypeIdentifiers

/// View tab lồng tiếng: chọn file SRT + video → cấu hình giọng → bấm lồng tiếng
struct DubbingView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 20) {
            if let task = vm.currentDubbingTask {
                DubbingTaskDetailView(task: task, vm: vm)
            } else {
                DubbingSetupView(vm: vm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Setup View (chưa có task)

struct DubbingSetupView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 55))
                .foregroundStyle(.blue)

            Text("Lồng tiếng")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Chọn file SRT → tạo file audio giọng đọc theo timestamp")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().frame(maxWidth: 400)

            // File SRT
            HStack {
                Text("File SRT:")
                    .frame(width: 80, alignment: .leading)

                if let srt = vm.dubbingSRTURL {
                    Text(srt.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 250, alignment: .leading)
                } else {
                    Text("Chưa chọn")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: 250, alignment: .leading)
                }

                Button("Chọn...") {
                    vm.pickSRTFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider().frame(maxWidth: 400)

            // Giọng đọc
            HStack {
                Text("Giọng đọc:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $vm.dubbingVoice) {
                    ForEach(DubbingVoice.allCases) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)

                Button {
                    vm.previewVoice()
                } label: {
                    if vm.isPreviewingVoice {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(vm.isPreviewingVoice)
                .help("Nghe thử giọng đọc")
            }

            // Button bắt đầu
            Button {
                vm.startDubbing()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Tạo file audio")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.dubbingSRTURL == nil)
            .padding(.top, 8)
        }
    }
}

// MARK: - Task Detail (đang chạy/hoàn tất)

struct DubbingTaskDetailView: View {

    @ObservedObject var task: DubbingTask
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(iconColor)

            Text(task.displayName)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("SRT: \(task.srtDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Giọng: \(task.voice.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Progress
            if task.status.isActive {
                VStack(spacing: 8) {
                    ProgressView(value: task.progress, total: 1)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(task.statusMessage)
                        Spacer()
                        Text("\(Int(task.progress * 100))%")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 450)
            } else if let installHint = Self.installHint(for: task.statusMessage), task.status.isError {
                // Hiển thị hướng dẫn cài đặt khi thiếu dependency
                VStack(spacing: 10) {
                    Text(task.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hướng dẫn cài đặt:")
                            .font(.caption)
                            .fontWeight(.semibold)

                        ForEach(installHint.steps, id: \.self) { step in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(step)
                                    .textSelection(.enabled)
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 450, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installHint.copyCommand, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy lệnh cài đặt")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: 450)
            } else {
                Text(task.statusMessage)
                    .font(.caption)
                    .foregroundStyle(task.status.isError ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }

            // Buttons
            HStack(spacing: 12) {
                if task.status.isActive {
                    Button("Hủy", role: .destructive) {
                        vm.cancelDubbing()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        vm.startDubbing()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text(task.status == .done ? "Lồng tiếng lại" : "Thử lại")
                        }
                        .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Tạo mới") {
                        vm.resetDubbing()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconColor: Color {
        switch task.status {
        case .idle, .queued: return .secondary
        case .running: return .blue
        case .done: return .green
        case .error: return .red
        }
    }

    // MARK: - Install Hints

    private struct InstallHint {
        let steps: [String]
        let copyCommand: String
    }

    private static func installHint(for message: String) -> InstallHint? {
        let lower = message.lowercased()

        if lower.contains("edge-tts") {
            return InstallHint(
                steps: [
                    "Mở Terminal trên máy",
                    "Chạy lệnh: pip3 install edge-tts",
                    "Nếu lỗi permission: pip3 install --user edge-tts",
                    "Sau đó mở lại app và thử lại"
                ],
                copyCommand: "pip3 install edge-tts"
            )
        } else if lower.contains("python") {
            return InstallHint(
                steps: [
                    "Cài Python3 qua Homebrew:",
                    "  brew install python3",
                    "Hoặc tải từ: https://www.python.org/downloads/",
                    "Sau khi cài xong, mở lại app"
                ],
                copyCommand: "brew install python3"
            )
        } else if lower.contains("ffmpeg") {
            return InstallHint(
                steps: [
                    "Cài FFmpeg qua Homebrew:",
                    "  brew install ffmpeg",
                    "Nếu chưa có Homebrew:",
                    "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                    "Sau khi cài xong, mở lại app"
                ],
                copyCommand: "brew install ffmpeg"
            )
        } else if lower.contains("faster-whisper") || lower.contains("whisper") {
            return InstallHint(
                steps: [
                    "Mở Terminal trên máy",
                    "Chạy lệnh: pip3 install faster-whisper",
                    "Nếu lỗi permission: pip3 install --user faster-whisper",
                    "Sau đó mở lại app và thử lại"
                ],
                copyCommand: "pip3 install faster-whisper"
            )
        }

        return nil
    }
}
