import SwiftUI

/// Thanh tab hiển thị danh sách video đang xử lý
struct TabBarView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(vm.tasks) { task in
                            TabChipView(
                                task: task,
                                isSelected: task.id == vm.selectedTaskID,
                                onSelect: { vm.selectedTaskID = task.id },
                                onClose: { vm.closeTask(task) }
                            )
                        }
                    }
                    .padding(.vertical, 10)
                }

                Spacer(minLength: 8)

                Button {
                    vm.showingFileImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .help("Thêm video")

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

            HStack {
                Text("\(vm.tasks.count) tab\(vm.tasks.count > 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}
