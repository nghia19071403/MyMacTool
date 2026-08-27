import SwiftUI

/// 1 dòng trong hàng đợi lồng tiếng hàng loạt.
struct DubbingTaskRow: View {

    @ObservedObject var task: DubbingTask
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.caption)

                Text(task.srtDisplayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let voice = task.clonedVoiceName {
                    Text("🎤 \(voice)")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(3)
                }

                Spacer()

                if task.status.isActive {
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Dừng khi đang chạy
                if task.status.isActive {
                    Button(action: onCancel) {
                        Image(systemName: "stop.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Dừng")
                }

                // Xóa khỏi hàng đợi
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Xóa")
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

    private var statusIcon: String {
        switch task.status {
        case .idle: return "circle"
        case .queued: return "clock"
        case .running: return "waveform.circle.fill"
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
