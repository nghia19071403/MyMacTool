import SwiftUI

/// Giao diện tab Bilibili / Douyin: ô nhập link + dropdown SRT + danh sách task
struct LinkInputView: View {

    let platform: LinkPlatform
    @ObservedObject var vm: AppViewModel

    private var linkTextBinding: Binding<String> {
        Binding(
            get: { vm.linkTexts[platform, default: ""] },
            set: { vm.linkTexts[platform] = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 18) {

            Image(systemName: platform.icon)
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text(platform.rawValue)
                .font(.headline)

            // Ô nhập link
            HStack(spacing: 8) {
                TextField(platform.placeholder, text: linkTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { vm.downloadFromLink(platform: platform) }

                Button {
                    vm.downloadFromLink(platform: platform)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(linkTextBinding.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Tải & tạo phụ đề")
            }
            .frame(maxWidth: 500)

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
            .frame(maxWidth: 500, alignment: .leading)

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
            .frame(maxWidth: 500, alignment: .leading)

            // Danh sách download tasks
            if let tasks = vm.downloadTasks[platform], !tasks.isEmpty {
                Divider().frame(maxWidth: 500)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tasks) { task in
                            DownloadTaskRow(
                                task: task,
                                onStop: { vm.stopDownload(task) },
                                onRetry: { vm.retryDownload(task) }
                            )
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: 500, maxHeight: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
