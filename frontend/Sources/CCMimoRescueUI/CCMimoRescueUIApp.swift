import SwiftUI

@main
struct CCMimoRescueUIApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: store.language.rawValue))
                .task {
                    await store.refreshHealth()
                    await store.refreshBackups()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
