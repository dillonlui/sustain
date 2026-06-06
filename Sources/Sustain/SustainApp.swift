import SwiftUI

@main
struct SustainApp: App {
    @StateObject private var store = AppStore.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Run System Check") {
                    store.runSystemCheck()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
