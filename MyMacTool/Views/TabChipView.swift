import SwiftUI

/// 1 chip trên thanh tab, đại diện cho 1 VideoTask
struct TabChipView: View {

    @ObservedObject var task: VideoTask

    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(task.displayName)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)

            if task.status.isActive {
                Text("\(Int(task.progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var dotColor: Color {
        switch task.status {
        case .idle: return .gray
        case .queued: return .orange
        case .running: return .blue
        case .done: return .green
        case .error: return .red
        }
    }
}
