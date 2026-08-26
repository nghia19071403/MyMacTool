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
}
