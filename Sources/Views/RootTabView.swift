import SwiftUI

struct RootTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            LibraryView()
                .tabItem { Label("书库", systemImage: "books.vertical.fill") }
                .tag(0)

            SpeakingHomeView()
                .tabItem { Label("口语", systemImage: "mic.fill") }
                .tag(1)
        }
        .tint(.orange)
        .onOpenURL { _ in
            // 从微信等外部打开的书先进书库
            selection = 0
        }
        .onAppear {
            // 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_SPEAKING=1` 启动时切到口语页
            if ProcessInfo.processInfo.environment["AUTO_OPEN_SPEAKING"] == "1" {
                selection = 1
            }
        }
    }
}
