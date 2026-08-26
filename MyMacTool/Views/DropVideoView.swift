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

            Button("Chọn video...") {
                vm.showingFileImporter = true
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
