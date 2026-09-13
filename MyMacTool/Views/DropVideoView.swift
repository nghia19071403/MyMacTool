import SwiftUI

/// Khu vực kéo-thả file video (tab "Kéo file")
struct DropVideoView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 16) {

            Image(systemName: vm.isTargeted ? "arrow.down.circle.fill" : "video.badge.plus")
                .font(.system(size: 55))
                .foregroundStyle(vm.isTargeted ? .blue : .secondary)

            Text(vm.isTargeted ? "Thả video vào đây" : "Kéo video vào đây")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Kéo nhiều file video cùng lúc để tạo nhiều tab, xử lý song song")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Dropdown chọn ngôn ngữ SRT
            HStack {
                Text("File phụ đề:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $vm.srtOutputOption) {
                    ForEach(SRTOutputOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 250)
            }

            // Setting số clip xử lý song song
            HStack {
                Text("Xử lý đồng thời:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $vm.maxConcurrentClips) {
                    Text("1 clip").tag(1)
                    Text("2 clips").tag(2)
                    Text("3 clips").tag(3)
                    Text("4 clips").tag(4)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)

                Text("(máy yếu chọn 1-2)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // OpenAI API key cho dịch chất lượng cao
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Dịch bằng OpenAI (tùy chọn):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    SecureField("Dán OpenAI API key (sk-...)", text: $vm.openaiAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)

                    Picker("", selection: $vm.openaiModel) {
                        Text("gpt-4o (tốt nhất)").tag("gpt-4o")
                        Text("gpt-4.1").tag("gpt-4.1")
                        Text("gpt-4.1-mini").tag("gpt-4.1-mini")
                        Text("gpt-4o-mini (rẻ)").tag("gpt-4o-mini")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160)
                }

                Text(vm.openaiAPIKey.isEmpty ? "Để trống = dùng Google/MyMemory miễn phí" : "✅ Sẽ ưu tiên dịch bằng OpenAI")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            Button("Chọn video...") {
                vm.showingFileImporter = true
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)

            // Danh sách video tasks — hiển thị bên dưới (giống tab Douyin)
            if !vm.tasks.isEmpty {
                Divider().frame(maxWidth: 500)

                // Thanh nút điều khiển chung
                HStack(spacing: 12) {
                    Text("\(vm.tasks.count) video")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        vm.startAllTasks()
                    } label: {
                        Label("Chạy tất cả", systemImage: "play.fill").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(role: .destructive) {
                        vm.stopAll()
                    } label: {
                        Label("Dừng tất cả", systemImage: "stop.fill").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!vm.hasActiveTasks)
                }
                .frame(maxWidth: 500)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(vm.tasks) { task in
                            VideoTaskRow(
                                task: task,
                                onStart: { vm.startTask(task) },
                                onStop: { vm.transcriptionService.cancel(task) },
                                onClose: { vm.closeTask(task) }
                            )
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: 500, maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
