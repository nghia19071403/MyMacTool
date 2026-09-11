import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Tab VoiceStudio: lồng tiếng qua server VoiceStudio local (OpenAI-compatible API).
/// Hoàn toàn tách biệt với tab Lồng tiếng (VieNeu-TTS).
struct VoiceStudioView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        Group {
            if let task = vm.currentVoiceStudioTask {
                VoiceStudioTaskDetailView(task: task, vm: vm)
            } else {
                VoiceStudioSetupView(vm: vm)
            }
        }
        .onAppear { vm.syncVoiceStudioConfig() }
    }
}

// MARK: - Setup View

struct VoiceStudioSetupView: View {

    @ObservedObject var vm: AppViewModel
    @State private var isDragOver = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 45))
                        .foregroundStyle(.teal)
                    Text("VoiceStudio")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Lồng tiếng qua VoiceStudio server (chạy local)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Kết nối server
                serverConfigSection

                Divider().frame(maxWidth: 420)

                // Khu vực kéo-thả SRT
                dropZone

                // File SRT đã chọn
                if let srt = vm.voiceStudioSRTURL {
                    HStack {
                        Image(systemName: "doc.text.fill").foregroundStyle(.teal)
                        Text(srt.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Đổi file") { vm.pickVoiceStudioSRTFile() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.teal.opacity(0.06))
                    .cornerRadius(8)
                    .frame(maxWidth: 420)
                } else {
                    Button("Chọn file SRT...") { vm.pickVoiceStudioSRTFile() }
                        .buttonStyle(.bordered)
                }

                // Chọn giọng
                HStack {
                    Text("Giọng:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("VD: alloy, echo, onyx...", text: $vm.voiceStudioVoice)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }

                // Button chạy
                Button {
                    vm.startVoiceStudio()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Tạo file audio")
                    }
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(vm.voiceStudioSRTURL == nil)
                .padding(.top, 4)

                // Hàng đợi
                if !vm.voiceStudioTasks.isEmpty {
                    queueSection
                }
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: Server config

    private var serverConfigSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Server:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .leading)
                TextField("http://127.0.0.1:8000", text: $vm.voiceStudioBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Button {
                    vm.checkVoiceStudioServer()
                } label: {
                    if vm.isCheckingVoiceStudioServer {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Kiểm tra")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isCheckingVoiceStudioServer)
            }

            HStack {
                Text("Model:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .leading)
                TextField("tts-1", text: $vm.voiceStudioModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }

            // Trạng thái kết nối
            HStack(spacing: 6) {
                Image(systemName: vm.voiceStudioServerOnline ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(vm.voiceStudioServerOnline ? .green : .orange)
                    .font(.caption)
                Text(vm.voiceStudioServerMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 420)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: isDragOver ? "arrow.down.circle.fill" : "waveform.circle")
                .font(.system(size: 40))
                .foregroundStyle(isDragOver ? .teal : .teal.opacity(0.7))
            Text(isDragOver ? "Thả file SRT vào đây" : "Kéo 1 hoặc nhiều file SRT")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDragOver ? Color.teal : Color.gray.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8]))
                .background(isDragOver ? Color.teal.opacity(0.05) : Color.clear)
                .cornerRadius(12)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleSRTDrop(providers)
        }
    }

    // MARK: Queue

    private var queueSection: some View {
        VStack(spacing: 6) {
            Divider().frame(maxWidth: 450).padding(.top, 8)
            HStack(spacing: 12) {
                Text("Hàng đợi (\(vm.voiceStudioTasks.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    vm.startAllVoiceStudio()
                } label: {
                    Label("Chạy tất cả", systemImage: "play.fill").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    vm.clearVoiceStudioTasks()
                } label: {
                    Label("Xóa hết", systemImage: "trash").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: 450)

            VStack(spacing: 2) {
                ForEach(vm.voiceStudioTasks) { task in
                    VoiceStudioTaskRow(
                        task: task,
                        onCancel: { vm.cancelVoiceStudioTask(task) },
                        onRemove: { vm.removeVoiceStudioTask(task) }
                    )
                    Divider()
                }
            }
            .frame(maxWidth: 450)
        }
    }

    private func handleSRTDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.pathExtension.lowercased() == "srt" {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            if urls.count == 1 {
                vm.voiceStudioSRTURL = urls[0]
            } else {
                vm.addVoiceStudioTasks(urls)
            }
        }
        return true
    }
}

// MARK: - Task Row

struct VoiceStudioTaskRow: View {

    @ObservedObject var task: VoiceStudioTask
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

                Text(task.voice)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.teal.opacity(0.12))
                    .cornerRadius(3)

                Spacer()

                if task.status.isActive {
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button(action: onCancel) {
                        Image(systemName: "stop.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
        case .running: return .teal
        case .done: return .green
        case .error: return .red
        }
    }
}

// MARK: - Task Detail View

struct VoiceStudioTaskDetailView: View {

    @ObservedObject var task: VoiceStudioTask
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(iconColor)

                Text(task.displayName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("SRT: \(task.srtDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "person.wave.2")
                        .font(.caption)
                        .foregroundStyle(.teal)
                    Text("Giọng: \(task.voice)")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.teal.opacity(0.1))
                .cornerRadius(6)

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

                HStack(spacing: 12) {
                    if task.status.isActive {
                        Button("Hủy", role: .destructive) {
                            vm.cancelVoiceStudio()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            vm.startVoiceStudio()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text(task.status == .done ? "Chạy lại" : "Thử lại")
                            }
                            .frame(minWidth: 160)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)

                        Button("Tạo mới") {
                            vm.resetVoiceStudio()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private var iconColor: Color {
        switch task.status {
        case .idle, .queued: return .secondary
        case .running: return .teal
        case .done: return .green
        case .error: return .red
        }
    }
}
