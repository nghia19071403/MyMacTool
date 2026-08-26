import SwiftUI

/// Chi tiết 1 video task đang được chọn
struct TaskDetailView: View {

    @ObservedObject var task: VideoTask
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 18) {

            Image(systemName: "video.fill")
                .font(.system(size: 50))
                .foregroundStyle(iconColor)

            Text(task.displayName)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                Label(task.videoDuration.isEmpty ? "--:--" : task.videoDuration, systemImage: "clock")
                Label(task.videoSize.isEmpty ? "--" : task.videoSize, systemImage: "internaldrive")
            }
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
                Button {
                    vm.startTask(task)
                } label: {
                    HStack {
                        if task.status.isActive {
                            ProgressView().controlSize(.small)
                            Text(task.status == .queued ? "Đang chờ..." : "Đang xử lý...")
                        } else {
                            Image(systemName: "play.fill")
                            Text(retryLabel)
                        }
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(task.status.isActive)

                if task.status.isActive {
                    Button("Hủy", role: .destructive) {
                        vm.transcriptionService.cancel(task)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Đóng tab", role: .destructive) {
                        vm.closeTask(task)
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

    private var retryLabel: String {
        switch task.status {
        case .done: return "Tạo lại SRT"
        case .error: return "Thử lại"
        default: return "Tạo file SRT"
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
