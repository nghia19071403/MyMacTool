import SwiftUI

/// 1 dòng hiển thị tiến độ tải của 1 link (với nút dừng/tải lại)
struct DownloadTaskRow: View {

    @ObservedObject var task: DownloadTask
    let onStop: () -> Void
    let onRetry: () -> Void

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

                if task.isDownloading {
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Nút Dừng
                if task.isDownloading {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Dừng tải")
                }

                // Nút Tải lại
                if task.errorMessage != nil && !task.isDownloading {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Tải lại")
                }
            }

            if task.isDownloading {
                ProgressView(value: task.progress, total: 1)
                    .progressViewStyle(.linear)
            }

            if let error = task.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(task.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        if task.errorMessage != nil { return "xmark.circle.fill" }
        if task.isCompleted { return "checkmark.circle.fill" }
        if task.isDownloading { return "arrow.down.circle.fill" }
        return "circle"
    }

    private var statusColor: Color {
        if task.errorMessage != nil { return .red }
        if task.isCompleted { return .green }
        if task.isDownloading { return .blue }
        return .gray
    }
}
