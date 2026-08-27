import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// View tab lồng tiếng: 2 sub-tab — "Lồng tiếng" và "Clone giọng"
struct DubbingView: View {

    @ObservedObject var vm: AppViewModel
    @State private var selectedTab: DubbingTab = .dubbing

    enum DubbingTab: String, CaseIterable {
        case dubbing = "Lồng tiếng"
        case cloneVoice = "Clone giọng"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab bar
            HStack(spacing: 0) {
                ForEach(DubbingTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tabIcon(tab))
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.subheadline)
                        }
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .dubbing:
                    if let task = vm.currentDubbingTask {
                        DubbingTaskDetailView(task: task, vm: vm)
                    } else {
                        DubbingSetupView(vm: vm)
                    }
                case .cloneVoice:
                    CloneVoiceView(vm: vm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }

    private func tabIcon(_ tab: DubbingTab) -> String {
        switch tab {
        case .dubbing: return "waveform"
        case .cloneVoice: return "mic.badge.plus"
        }
    }
}

// MARK: - Clone Voice View

struct CloneVoiceView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 45))
                    .foregroundStyle(.purple)

                Text("Clone giọng nói")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Chọn file audio 3-8 giây → tạo giọng mới")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider().frame(maxWidth: 400)

                // File audio reference
                HStack {
                    Text("File mẫu:")
                        .frame(width: 80, alignment: .leading)

                    if let ref = vm.cloneRefAudioURL {
                        Text(ref.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 250, alignment: .leading)
                    } else {
                        Text("Chưa chọn (WAV/MP3, 3-8s)")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: 250, alignment: .leading)
                    }

                    Button("Chọn...") {
                        vm.pickCloneAudioFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Tên giọng
                HStack {
                    Text("Tên giọng:")
                        .frame(width: 80, alignment: .leading)

                    TextField("VD: Giọng của tôi", text: $vm.cloneVoiceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)
                }

                // Danh sách giọng đã clone
                if !vm.clonedVoices.isEmpty {
                    Divider().frame(maxWidth: 400)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Giọng đã clone (\(vm.clonedVoices.count)):")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(vm.clonedVoices) { voice in
                            HStack {
                                Image(systemName: "person.wave.2.fill")
                                    .foregroundStyle(.purple)
                                Text(voice.name)
                                    .font(.callout)
                                Spacer()
                                Text(voice.audioURL.lastPathComponent)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Button {
                                    vm.removeClonedVoice(voice)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: 400, alignment: .leading)
                }

                // Status
                if vm.isCloning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(vm.cloneStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !vm.cloneStatusMessage.isEmpty {
                    Text(vm.cloneStatusMessage)
                        .font(.caption)
                        .foregroundStyle(vm.cloneStatusMessage.contains("Lỗi") ? .red : .green)
                }

                // Preview sau khi clone xong
                if vm.clonePreviewReady {
                    VStack(spacing: 10) {
                        Text("Nghe thử giọng vừa clone:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                vm.playClonePreview()
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Nghe thử")
                                }
                            }
                            .buttonStyle(.bordered)

                            Button {
                                vm.confirmAddClonedVoice()
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Thêm vào danh sách")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            Button("Bỏ qua", role: .destructive) {
                                vm.discardClonePreview()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                // Button clone
                Button {
                    vm.cloneVoice()
                } label: {
                    HStack {
                        Image(systemName: "waveform.badge.plus")
                        Text("Clone giọng")
                    }
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(vm.cloneRefAudioURL == nil || vm.cloneVoiceName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isCloning || vm.clonePreviewReady)
                .padding(.top, 8)
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Dubbing Setup View

struct DubbingSetupView: View {

    @ObservedObject var vm: AppViewModel
    @State private var isDragOver = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // Khu vực kéo-thả file SRT
                VStack(spacing: 12) {
                    Image(systemName: isDragOver ? "arrow.down.circle.fill" : "waveform.circle.fill")
                        .font(.system(size: 45))
                        .foregroundStyle(isDragOver ? .blue : .blue.opacity(0.8))

                    Text(isDragOver ? "Thả file SRT vào đây" : "Lồng tiếng")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Kéo file SRT vào đây hoặc bấm chọn")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDragOver ? Color.blue : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .background(isDragOver ? Color.blue.opacity(0.05) : Color.clear)
                        .cornerRadius(12)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleSRTDrop(providers)
                }

                // File SRT đã chọn
                if let srt = vm.dubbingSRTURL {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.blue)
                        Text(srt.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Đổi file") {
                            vm.pickSRTFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                    .frame(maxWidth: 400)
                } else {
                    Button("Chọn file SRT...") {
                        vm.pickSRTFile()
                    }
                    .buttonStyle(.bordered)
                }

                Divider().frame(maxWidth: 400)

                // Giọng đọc — ưu tiên clone lên đầu
                HStack {
                    Text("Giọng đọc:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $vm.dubbingVoiceSelection) {
                        // Giọng đã clone (ưu tiên đầu tiên)
                        if !vm.clonedVoices.isEmpty {
                            Section("🎤 Giọng đã clone") {
                                ForEach(vm.clonedVoices) { voice in
                                    Text("🎤 \(voice.name)").tag(VoiceSelection.cloned(voice.id))
                                }
                            }
                        }
                        // Giọng có sẵn
                        Section("Giọng có sẵn") {
                            ForEach(DubbingVoice.allCases) { voice in
                                Text(voice.displayName).tag(VoiceSelection.preset(voice))
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)

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

                // Lịch sử lồng tiếng
                if !vm.dubbingHistory.isEmpty {
                    Divider().frame(maxWidth: 450).padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Lịch sử")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Xóa") {
                                vm.clearDubbingHistory()
                            }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                        .frame(maxWidth: 450)

                        ForEach(vm.dubbingHistory.prefix(5)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(item.success ? .green : .red)

                                Text(item.srtName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(item.voiceLabel)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(3)

                                Spacer()

                                Text(item.dateFormatted)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                if item.success, let outputPath = item.outputPath {
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
                                    } label: {
                                        Image(systemName: "folder")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .frame(maxWidth: 450)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func handleSRTDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "srt" else { return }
                DispatchQueue.main.async {
                    vm.dubbingSRTURL = url
                }
            }
        }
        return true
    }
}

// MARK: - Task Detail View

struct DubbingTaskDetailView: View {

    @ObservedObject var task: DubbingTask
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
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

                // Hiện giọng đang sử dụng
                HStack(spacing: 4) {
                    Image(systemName: task.clonedVoiceName != nil ? "mic.fill" : "person.wave.2")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("Giọng: \(task.clonedVoiceName ?? task.voice.displayName)")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(6)

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

                // Lịch sử bên dưới
                if !vm.dubbingHistory.isEmpty {
                    Divider().frame(maxWidth: 450).padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Lịch sử")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Xóa") {
                                vm.clearDubbingHistory()
                            }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                        .frame(maxWidth: 450)

                        ForEach(vm.dubbingHistory.prefix(5)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(item.success ? .green : .red)

                                Text(item.srtName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(item.voiceLabel)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(3)

                                Spacer()

                                Text(item.dateFormatted)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                if item.success, let outputPath = item.outputPath {
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
                                    } label: {
                                        Image(systemName: "folder")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .frame(maxWidth: 450)
                        }
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
        case .running: return .blue
        case .done: return .green
        case .error: return .red
        }
    }
}
