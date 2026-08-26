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
}
