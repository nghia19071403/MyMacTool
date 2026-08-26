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

            Text("Lồng tiếng video")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Chọn file SRT + video gốc → tạo video lồng tiếng tự động")
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

            // File Video
            HStack {
                Text("Video gốc:")
                    .frame(width: 80, alignment: .leading)

                if let video = vm.dubbingVideoURL {
                    Text(video.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 250, alignment: .leading)
                } else {
                    Text("Chưa chọn")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: 250, alignment: .leading)
                }

                Button("Chọn...") {
                    vm.pickVideoFile()
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

            // Tốc độ
            HStack {
                Text("Tốc độ:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $vm.dubbingSpeed) {
                    Text("Chậm (-20%)").tag("-20%")
                    Text("Hơi chậm (-10%)").tag("-10%")
                    Text("Bình thường").tag("+0%")
                    Text("Hơi nhanh (+10%)").tag("+10%")
                    Text("Nhanh (+20%)").tag("+20%")
                    Text("Rất nhanh (+30%)").tag("+30%")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            // Giữ audio gốc
            HStack {
                Toggle("Giữ audio gốc (mix nhỏ)", isOn: $vm.dubbingKeepOriginal)
                    .font(.caption)
                    .toggleStyle(.checkbox)

                if vm.dubbingKeepOriginal {
                    Text("Volume gốc: \(Int(vm.dubbingOriginalVolume * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Slider(value: $vm.dubbingOriginalVolume, in: 0.05...0.5, step: 0.05)
                        .frame(maxWidth: 100)
                }
            }

            // Button bắt đầu
            Button {
                vm.startDubbing()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Bắt đầu lồng tiếng")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.dubbingSRTURL == nil || vm.dubbingVideoURL == nil)
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
