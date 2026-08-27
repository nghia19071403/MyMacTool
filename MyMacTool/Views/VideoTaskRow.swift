import SwiftUI

/// 1 dòng hiển thị tiến độ xử lý (tạo SRT) của 1 video trong tab "Kéo file".
/// Bố cục giống DownloadTaskRow của tab Douyin: hiển thị bên dưới, nút thao tác trong row.
struct VideoTaskRow: View {

    @ObservedObject var task: VideoTask
    let onStart: () -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.caption)

                Text(task.displayName)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()

                if task.status.isActive {
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Nút Chạy (khi chưa chạy)
                if !task.status.isActive {
                    Button(action: onStart) {
                        Image(systemName: "play.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help(startHelp)
                }

                // Nút Dừng (khi đang chạy)
                if task.status.isActive {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Dừng")
                }

                // Nút Đóng
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Đóng")
            }

            if task.status.isActive {
                ProgressView(value: task.progress, total: 1)
                    .progressViewStyle(.linear)
            }

            Text(task.statusMessage)
                .font(.caption2)
                .foregroundStyle(task.status.isError ? .red : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var startHelp: String {
        switch task.status {
        case .done: return "Tạo lại SRT"
        case .error: return "Thử lại"
        default: return "Tạo file SRT"
        }
    }

    private var statusIcon: String {
        switch task.status {
        case .idle, .queued: return "circle"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .idle: return .gray
        case .queued: return .orange
        case .running: return .blue
        case .done: return .green
        case .error: return .red
        }
    }
}
