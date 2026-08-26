import SwiftUI

/// Sidebar 3 tab: Bilibili, Douyin, Kéo file
struct SidebarView: View {

    @ObservedObject var vm: AppViewModel

    var body: some View {
        List(SidebarItem.allCases, selection: $vm.selectedSidebarItem) { item in
            HStack {
                Label(item.title, systemImage: item.icon)
                Spacer()
                if vm.isRunning(item) {
                    ProgressView().controlSize(.small)
                }
            }
            .tag(item)
        }
        .navigationTitle("Nguồn video")
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }
}
