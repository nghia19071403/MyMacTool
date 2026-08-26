import SwiftUI
import UniformTypeIdentifiers

/// View chính: NavigationSplitView với sidebar + detail.
/// Không chứa logic — chỉ bind vào AppViewModel.
struct ContentView: View {

    @StateObject private var vm = AppViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(vm: vm)
        } detail: {
            MainContentView(vm: vm)
        }
        .onChange(of: vm.selectedSidebarItem) { _ in
            vm.onSidebarChanged()
        }
    }
}

/// Nội dung bên phải (detail) của NavigationSplitView
struct MainContentView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {

            // Tab bar chỉ hiện khi ở tab "Kéo file" và có video
            if vm.selectedSidebarItem == .localFile, !vm.tasks.isEmpty {
                TabBarView(vm: vm)
                Divider()
            }

            Group {
                if let selected = vm.selectedTask {
                    TaskDetailView(task: selected, vm: vm)
                } else {
                    switch vm.selectedSidebarItem {
                    case .platform(let platform):
                        LinkInputView(platform: platform, vm: vm)
                    case .localFile:
                        DropVideoView(vm: vm)
                    case .dubbing:
                        DubbingView(vm: vm)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 420, idealHeight: 480)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    vm.isTargeted ? Color.blue : Color.gray.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: vm.tasks.isEmpty ? [8] : [])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $vm.isTargeted) { providers in
            vm.handleDrop(providers)
        }
        .fileImporter(
            isPresented: $vm.showingFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls { vm.addTask(for: url) }
            }
        }
    }
}
